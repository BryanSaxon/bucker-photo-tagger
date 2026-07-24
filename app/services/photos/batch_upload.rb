module Photos
  # Creates an unprocessed Photo for every uploaded image, expanding any .zip
  # archives into their contained images, and stamps the chosen catalog context
  # (community / floorplan / room) onto each one.
  #
  # The context is normalized first: a lone floorplan or room back-fills the
  # community, and an inconsistent combination is rejected up front so no photos
  # are created.
  class BatchUpload
    Result = Struct.new(:created, :errors, keyword_init: true) do
      def success? = errors.empty?
      def count = created.size
    end

    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .gif].freeze
    CONTENT_TYPES = {
      ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
      ".webp" => "image/webp", ".gif" => "image/gif"
    }.freeze
    MAX_ZIP_ENTRIES = 1000 # guard against zip bombs

    def self.call(...) = new(...).call

    def initialize(files:, community_id: nil, floorplan_id: nil, room_id: nil)
      @files = Array(files).reject(&:blank?)
      @community_id = community_id.presence
      @floorplan_id = floorplan_id.presence
      @room_id = room_id.presence
    end

    def call
      return Result.new(created: [], errors: [ "Please choose at least one file to upload." ]) if @files.empty?

      context = resolve_context
      return context if context.is_a?(Result)

      created = []
      errors = []
      @files.each { |file| ingest(file, context, created, errors) }

      if created.empty? && errors.empty?
        errors << "No images were found in the uploaded file(s)."
      end
      Result.new(created: created, errors: errors)
    end

    private

    def ingest(file, context, created, errors)
      if zip?(file)
        expand_zip(file, context, created, errors)
      elsif image?(file.original_filename)
        photo = build(io: file, filename: file.original_filename,
          content_type: file.content_type, context: context)
        record(photo, file.original_filename, created, errors)
      else
        errors << "#{file.original_filename}: unsupported file type (skipped)."
      end
    end

    def expand_zip(file, context, created, errors)
      count = 0
      Zip::File.open_buffer(file.tempfile) do |zip|
        zip.each do |entry|
          next unless entry.file? && image?(entry.name) && !hidden?(entry.name)

          count += 1
          if count > MAX_ZIP_ENTRIES
            errors << "#{file.original_filename}: stopped after #{MAX_ZIP_ENTRIES} images."
            break
          end

          io = StringIO.new(entry.get_input_stream.read)
          photo = build(io: io, filename: File.basename(entry.name),
            content_type: content_type_for(entry.name), context: context)
          record(photo, entry.name, created, errors)
        end
      end
    rescue StandardError => e
      errors << "#{file.original_filename}: could not read archive (#{e.class})."
    end

    def build(io:, filename:, content_type:, context:)
      photo = Photo.new(
        name: File.basename(filename.to_s, ".*").presence || "photo",
        community_id: context[:community_id],
        floorplan_id: context[:floorplan_id],
        room_id: context[:room_id]
      )
      photo.image.attach(io: io, filename: filename, content_type: content_type)
      photo
    end

    def record(photo, label, created, errors)
      if photo.save
        created << photo
      else
        errors << "#{label}: #{photo.errors.full_messages.to_sentence}"
      end
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

      { community_id: community_id, floorplan_id: floorplan&.id, room_id: room&.id }
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
