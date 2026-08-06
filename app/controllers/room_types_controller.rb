class RoomTypesController < ApplicationController
  before_action :require_admin
  before_action :set_room_type, only: %i[update destroy]

  # The room vocabulary is Signature's, not ours — config/room_types.yml only
  # seeds it, and staff adjust the wording and ordering here without a deploy.
  def index
    @room_types = RoomType.ordered
    @room_type = RoomType.new
  end

  def create
    @room_type = RoomType.new(room_type_params)
    @room_type.key ||= @room_type.name.to_s.parameterize(separator: "_")
    # New types land at the end; ordering is managed by dragging.
    @room_type.sort_order = RoomType.maximum(:sort_order).to_i + 10

    if @room_type.save
      redirect_to room_types_path, notice: "Added “#{@room_type.name}”."
    else
      @room_types = RoomType.ordered
      flash.now[:alert] = @room_type.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @room_type.update(room_type_params.except(:key))
      redirect_to room_types_path, notice: "Updated “#{@room_type.name}”."
    else
      redirect_to room_types_path, alert: @room_type.errors.full_messages.to_sentence
    end
  end

  # Deactivate rather than delete when a type is in use: photos already tagged
  # with it keep their placement, it just stops being offered on new work.
  def destroy
    if @room_type.photos.exists? || @room_type.rooms.exists?
      @room_type.update!(active: false)
      redirect_to room_types_path,
        notice: "“#{@room_type.name}” is in use, so it was hidden rather than deleted.",
        status: :see_other
    else
      @room_type.destroy
      redirect_to room_types_path, notice: "Removed “#{@room_type.name}”.", status: :see_other
    end
  end

  # Persist a drag-to-reorder. The submitted id sequence is the new order;
  # positions are re-derived from it rather than trusted from the client.
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    known = RoomType.where(id: ids).pluck(:id).to_set

    RoomType.transaction do
      ids.each_with_index do |id, index|
        next unless known.include?(id)

        RoomType.where(id: id).update_all(sort_order: (index + 1) * 10)
      end
    end

    head :no_content
  end

  private

  def set_room_type
    @room_type = RoomType.find(params[:id])
  end

  def room_type_params
    params.require(:room_type).permit(:key, :name, :active)
  end
end
