module Photos
  # Creates an unprocessed Photo for every uploaded image, expanding any .zip
  # archives into their contained images, and stamps the chosen catalog context
  # (community / floorplan / room) onto each one.
  #
  # The context is normalized first: a lone floorplan or room back-fills the
  # community, and an inconsistent combination is rejected up front so no photos
  # are created.
  class BatchUpload
    Result = Struct.new(:created, :updated, :errors, keyword_init: true) do
      def initialize(created: [], updated: [], errors: [])
        super
      end

      def success? = errors.empty?
      def count = created.size
      def updated_count = updated.size
    end

    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .gif].freeze
    # Accepted only where libvips can actually decode HEIF (see
    # Photos::ImageSupport); Photos::PrepareImageJob converts them to JPEG on
    # ingest. Where it can't, they are rejected with guidance rather than
    # silently producing a broken thumbnail.
    HEIC_EXTENSIONS = %w[.heic .heif].freeze
    CONTENT_TYPES = {
      ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
      ".webp" => "image/webp", ".gif" => "image/gif",
      ".heic" => "image/heic", ".heif" => "image/heif"
    }.freeze
    MAX_ZIP_ENTRIES = 1000 # guard against zip bombs

    def self.call(...) = new(...).call

    def initialize(files: nil, signed_ids: nil, community_id: nil, floorplan_id: nil,
      room_id: nil, room_type_id: nil, update_existing: true)
      @files = Array(files).reject(&:blank?)
      @signed_ids = Array(signed_ids).reject(&:blank?)
      @community_id = community_id.presence
      @floorplan_id = floorplan_id.presence
      @room_id = room_id.presence
      @room_type_id = room_type_id.presence
      @update_existing = update_existing
    end

    def call
      if @files.empty? && @signed_ids.empty?
        return Result.new(created: [], errors: [ "Please choose at least one file to upload." ])
      end

      context = resolve_context
      return context if context.is_a?(Result)

      @context_cache = context

      created = []
      errors = []
      @updated = []
      # Images uploaded straight to storage arrive as signed blob ids; zips (and
      # any non-direct-upload files) still stream through here.
      @signed_ids.each { |signed_id| ingest_signed_id(signed_id, context, created, errors) }
      @files.each { |file| ingest(file, context, created, errors) }

      if created.empty? && @updated.empty? && errors.empty?
        errors << "No images were found in the uploaded file(s)."
      end
      Result.new(created: created, updated: @updated, errors: errors)
    end

    private

    # Attach an already-uploaded blob (no bytes pass through the server).
    def ingest_signed_id(signed_id, context, created, errors)
      blob = ActiveStorage::Blob.find_signed!(signed_id)
      filename = blob.filename.to_s

      # The direct-upload path must apply the same allowlist #ingest does. The
      # browser routes anything reporting image/* here — including HEIC, which
      # libvips can't decode in this deployment — so without this check a Photo
      # was created and its thumbnail then failed silently in the background.
      unless accepted?(filename)
        blob.purge_later # otherwise the rejected upload pays R2 storage forever
        errors << unsupported_message(filename)
        return
      end

      photo = Photo.new(
        name: File.basename(filename, ".*").presence || "photo",
        community_id: context[:community_id],
        floorplan_id: context[:floorplan_id],
        room_id: context[:room_id],
        room_type_id: context[:room_type_id]
      )
      photo.image.attach(blob)
      record(photo, filename, created, errors)
    rescue StandardError => e
      errors << "An uploaded file could not be attached (#{e.class})."
    end

    def ingest(file, context, created, errors)
      if zip?(file)
        expand_zip(file, context, created, errors)
      elsif accepted?(file.original_filename)
        photo = build(io: file, filename: file.original_filename,
          content_type: file.content_type, context: context)
        record(photo, file.original_filename, created, errors)
      else
        errors << unsupported_message(file.original_filename)
      end
    end

    def heic?(filename)
      HEIC_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
    end

    # Acceptable either because we can render it directly, or because we can
    # convert it on ingest.
    def accepted?(filename)
      image?(filename) || (heic?(filename) && ImageSupport.heic_available?)
    end

    # HEIC/HEIF gets its own guidance: it's the common iPhone default and the
    # fix is a camera setting, not something the designer can guess at.
    def unsupported_message(filename)
      if heic?(filename)
        "#{filename}: HEIC photos aren’t supported yet — on iPhone, set " \
          "Settings → Camera → Formats → Most Compatible, or export as JPEG."
      else
        "#{filename}: unsupported file type (skipped)."
      end
    end

    # Stream the archive from disk and spill each image to its own tempfile
    # rather than reading whole entries into memory — keeps peak memory ~one
    # streaming buffer regardless of how many (or how large) the photos are.
    def expand_zip(file, context, created, errors)
      count = 0
      Zip::File.open(file.tempfile.path) do |zip|
        zip.each do |entry|
          next unless entry.file? && accepted?(entry.name) && !hidden?(entry.name)

          count += 1
          if count > MAX_ZIP_ENTRIES
            errors << "#{file.original_filename}: stopped after #{MAX_ZIP_ENTRIES} images."
            break
          end

          extract_entry(entry, context, created, errors)
        end
      end
    rescue StandardError => e
      errors << "#{file.original_filename}: could not read archive (#{e.class})."
    end

    def extract_entry(entry, context, created, errors)
      tmp = Tempfile.new([ "zip-entry", File.extname(entry.name) ], binmode: true)
      entry.get_input_stream { |input| IO.copy_stream(input, tmp) }
      tmp.rewind
      photo = build(io: tmp, filename: File.basename(entry.name),
        content_type: content_type_for(entry.name), context: context)
      record(photo, entry.name, created, errors)
    ensure
      tmp&.close!
    end

    def build(io:, filename:, content_type:, context:)
      photo = Photo.new(
        name: File.basename(filename.to_s, ".*").presence || "photo",
        community_id: context[:community_id],
        floorplan_id: context[:floorplan_id],
        room_id: context[:room_id],
        room_type_id: context[:room_type_id]
      )
      photo.image.attach(io: io, filename: filename, content_type: content_type)
      photo
    end

    # A re-upload of a photo already in the library is not a mistake to warn
    # about: designers re-upload from phone albums that are organised by
    # community and floorplan precisely so that placement comes with them. So
    # carry the new placement onto the existing photo rather than duplicating
    # it, and never touch its tags, pins or processed state.
    def record(photo, label, created, errors)
      existing = @update_existing ? DuplicateFinder.for_blob(photo.image.blob) : nil

      if existing
        apply_placement(existing)
        # Only a direct upload has persisted its blob already; one attached to
        # an unsaved record has no id yet and nothing to purge.
        photo.image.blob.purge_later if photo.image.blob&.persisted?
        @updated << existing
        return
      end

      if photo.save
        created << photo
      else
        errors << "#{label}: #{photo.errors.full_messages.to_sentence}"
      end
    end

    # Only ever fills in or improves placement. A re-upload with nothing chosen
    # on the form must not blank out what the photo already had.
    def apply_placement(photo)
      changes = {
        community_id: @context_cache[:community_id],
        floorplan_id: @context_cache[:floorplan_id],
        room_id: @context_cache[:room_id],
        room_type_id: @context_cache[:room_type_id]
      }.compact

      photo.update(changes) if changes.any?
    end

    # Normalize the trio: derive community from a lone floorplan/room and reject
    # an inconsistent combination. Returns a context hash or a failed Result.
    def resolve_context
      floorplan = @floorplan_id && Floorplan.find_by(id: @floorplan_id)
      room = @room_id && Room.find_by(id: @room_id)
      community_id = (@community_id && @community_id.to_i) || floorplan&.community_id || room&.community_id

      if floorplan && community_id && floorplan.community_id != community_id
        return Result.new(created: [], errors: [ "The selected plan is not in the selected community." ])
      end
      if room && community_id && room.community_id != community_id
        return Result.new(created: [], errors: [ "The selected room is not in the selected community." ])
      end

      # A chosen catalog room already implies its designer-facing type.
      room_type_id = @room_type_id || room&.room_type_id
      { community_id: community_id, floorplan_id: floorplan&.id, room_id: room&.id,
        room_type_id: room_type_id }
    end

    def zip?(file)
      name = file.original_filename.to_s.downcase
      name.end_with?(".zip") ||
        %w[application/zip application/x-zip-compressed multipart/x-zip].include?(file.content_type)
    end

    def image?(filename)
      IMAGE_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
    end

    def hidden?(name)
      base = File.basename(name)
      name.start_with?("__MACOSX") || base.start_with?(".")
    end

    def content_type_for(filename)
      CONTENT_TYPES[File.extname(filename.to_s).downcase] || "application/octet-stream"
    end
  end
end
