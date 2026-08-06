class PhotosController < ApplicationController
  before_action :set_photo, only: %i[show update destroy sku_search selected_sku_row]

  # Index defaults to photos that still need processing, with a toggle for
  # completed photos, a name search, and a queue of photos tagged before
  # finishes could be recorded.
  def index
    @show_completed = params[:status] == "complete"
    @missing_variants = params[:filter] == "missing_variants"
    @query = params[:q].to_s.strip

    # Count over the SEARCHED set, not the whole library. Previously the tabs
    # showed unfiltered totals, so a search could read "Completed 812" above an
    # empty grid — and a completed photo was unreachable from this tab, which
    # looks like the photo isn't in the system at all.
    matched = Photo.search(@query)
    counts = matched.group(:status).count
    @unprocessed_count = counts["unprocessed"].to_i
    @complete_count = counts["complete"].to_i
    @missing_variants_count = matched.complete.missing_variants.count

    scope = @show_completed ? matched.complete : matched.unprocessed
    scope = scope.missing_variants if @missing_variants
    @pagy, @photos = pagy(scope.recent.with_attached_image)
  end

  def new
    @photo = Photo.new
    load_upload_data
  end

  # Accepts a batch of images and/or .zip archives, expands the archives, and
  # creates an unprocessed Photo for each image — stamped with the optional
  # community / plan / room context chosen on the form.
  def create
    result = Photos::BatchUpload.call(
      files: params.dig(:photo, :images),
      signed_ids: params.dig(:photo, :signed_ids),
      community_id: upload_params[:community_id],
      floorplan_id: upload_params[:floorplan_id],
      room_id: upload_params[:room_id],
      room_type_id: upload_params[:room_type_id]
    )

    if result.count.positive?
      notice = "Uploaded #{result.count} #{'photo'.pluralize(result.count)}. Ready to process."
      notice += " #{result.errors.size} #{'file'.pluralize(result.errors.size)} skipped." if result.errors.any?
      redirect_to photos_path, notice: notice
    else
      @photo = Photo.new
      load_upload_data
      flash.now[:alert] = result.errors.to_sentence.presence || "Upload failed."
      render :new, status: :unprocessable_entity
    end
  end

  # Processing screen (also used to re-edit completed photos).
  def show
    load_processing_data
  end

  def update
    result = Photos::SaveSelections.call(
      photo: @photo,
      community_id: photo_params[:community_id],
      floorplan_id: photo_params[:floorplan_id],
      room_id: photo_params[:room_id],
      room_type_id: photo_params[:room_type_id],
      sku_entries: photo_params[:skus] || [],
      user: Current.user
    )

    if result.success?
      redirect_to photos_path, notice: "“#{@photo.name}” saved and marked complete."
    else
      load_processing_data
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @photo.destroy
    redirect_to photos_path, notice: "Photo deleted.", status: :see_other
  end

  # Live SKU search results rendered into the processing panel's Turbo frame.
  # When `scoped` is on, results are narrowed to products available for the
  # photo's captured community/room context.
  def sku_search
    @query = params[:q].to_s.strip
    @scoped = ActiveModel::Type::Boolean.new.cast(params[:scoped])

    skus = Sku.search(@query).in_category(params[:category])
    skus = skus.for_context(community_id: @photo.community_id, room_id: @photo.room_id) if @scoped
    @skus = skus.ordered.limit(50)
    # (sku_id, variant) pairs — a product with variants can be added more than
    # once, so it stays selectable after the first pick.
    @selected_keys = @photo.photo_skus.pluck(:sku_id, :variant_value)
    render partial: "photos/sku_results", locals: { skus: @skus, selected_keys: @selected_keys }
  end

  # One row of the selected-SKU list, rendered on the server so the partial
  # stays the single source of truth for the markup — the variant picker's
  # options come straight off the Sku record rather than being rebuilt in JS.
  def selected_sku_row
    sku = Sku.find(params[:sku_id])
    render partial: "photos/selected_sku",
      locals: { sku: sku, variant_value: "", pos_x: nil, pos_y: nil }
  end

  private

  def set_photo
    @photo = Photo.find(params[:id])
  end

  # Compact catalog data for the upload form's cascading Community/Plan/Room
  # selects. Rooms carry their community_id so the client can filter them once a
  # community is known (directly or via a chosen plan).
  def load_upload_data
    @communities = Community.ordered
    @room_types = RoomType.available.ordered
    @floorplans = Floorplan.ordered.pluck(:id, :name, :elevation, :community_id)
    @rooms = Room.order(:room_desc, :room_code).pluck(:id, :room_desc, :room_code, :community_id)
  end

  def load_processing_data
    @communities = Community.ordered
    @room_types = RoomType.available.ordered
    @floorplans = Floorplan.includes(:community).ordered
    # All rooms are rendered (filtered client-side by community, like floorplans)
    # so a room stays selectable even if the community is changed here.
    @rooms = Room.order(:room_desc, :room_code)
    # Ordered so pin numbering stays stable across reloads.
    @photo_skus = @photo.photo_skus.includes(:sku).order(:id)
    @category_codes = Sku.category_codes
    # Does the photo's context actually resolve to any products? Drives whether
    # the "limit to this location" scoping is offered/defaulted on.
    @context_scope_available = @photo.community_id.present? &&
      Sku.for_context(community_id: @photo.community_id, room_id: @photo.room_id).exists?
  end

  def upload_params
    params.require(:photo).permit(:community_id, :floorplan_id, :room_id, :room_type_id)
  end

  def photo_params
    params.require(:photo).permit(:community_id, :floorplan_id, :room_id, :room_type_id,
      skus: %i[id pos_x pos_y variant_value])
  end
end
