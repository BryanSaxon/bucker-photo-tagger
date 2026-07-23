class PhotoSku < ApplicationRecord
  belongs_to :photo
  belongs_to :sku

  validates :sku_id, uniqueness: { scope: :photo_id }

  # Coordinates are normalized (0.0–1.0) so they survive any image resize.
  validates :pos_x, :pos_y,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true

  def pinned?
    pos_x.present? && pos_y.present?
  end
end
