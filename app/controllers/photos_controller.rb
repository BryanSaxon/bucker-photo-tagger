class PhotosController < ApplicationController
  before_action :set_photo, only: %i[show update destroy sku_search]

  # Index defaults to photos that still need processing, with a toggle for
  # completed photos and a name search.
  def index
    @show_completed = params[:status] == "complete"
    @query = params[:q].to_s.strip

    scope = @show_completed ? Photo.complete : Photo.unprocessed
    scope = scope.search(@query)
    @photos = scope.recent.with_attached_image

    @unprocessed_count = Photo.unprocessed.count
    @complete_count = Photo.complete.count
  end

  def new
    @photo = Photo.new
  end

  # Accepts one or more uploaded images and creates an unprocessed Photo for each.
  def create
    files = Array(params.dig(:photo, :images)).reject(&:blank?)

    if files.empty?
      @photo = Photo.new
      flash.now[:alert] = "Please choose at least one photo to upload."
      return render :new, status: :unprocessable_entity
    end

    created = files.map do |file|
      photo = Photo.new(name: File.basename(file.original_filename, ".*"))
      photo.image.attach(file)
      photo.save
      photo
    end

    if created.all?(&:persisted?)
      redirect_to photos_path, notice: "Uploaded #{created.size} #{'photo'.pluralize(created.size)}. Ready to process."
    else
      @photo = created.find { |p| !p.persisted? } || Photo.new
      flash.now[:alert] = "Some photos could not be uploaded: #{@photo.errors.full_messages.to_sentence}"
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
  def sku_search
    @query = params[:q].to_s.strip
    @skus = Sku.search(@query).in_category(params[:category]).ordered.limit(50)
    @selected_ids = @photo.sku_ids
    render partial: "photos/sku_results", locals: { skus: @skus, selected_ids: @selected_ids }
  end

  private

  def set_photo
    @photo = Photo.find(params[:id])
  end

  def load_processing_data
    @communities = Community.ordered
    @floorplans = Floorplan.includes(:community).ordered
    @photo_skus = @photo.photo_skus.includes(:sku)
    @category_codes = Sku.category_codes
  end

  def photo_params
    params.require(:photo).permit(:community_id, :floorplan_id, skus: %i[id pos_x pos_y])
  end
end
