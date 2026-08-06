class PhotoSku < ApplicationRecord
  belongs_to :photo
  belongs_to :sku

  # A tag is identified by (photo, sku, variant) — the same product in two
  # finishes is two tags on one photo, each with its own pin.
  validates :sku_id, uniqueness: { scope: %i[photo_id variant_value] }
  validates :variant_value, length: { maximum: 100 }

  normalizes :variant_value, with: ->(value) { value.to_s.strip }

  # Coordinates are normalized (0.0–1.0) so they survive any image resize.
  validates :pos_x, :pos_y,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true

  scope :with_variant, -> { where.not(variant_value: "") }

  def pinned?
    pos_x.present? && pos_y.present?
  end

  def variant? = variant_value.present?

  # Deliberately not a validation. The source catalog lists variant choices for
  # only some products and can't describe a finish it doesn't carry, so free
  # text is legitimate — but it's still worth being able to tell the two apart.
  def variant_in_catalog? = variant? && sku.attribute_choices.include?(variant_value)

  # Identity of this tag within a photo, used to key pin markers in the UI.
  def row_key = "#{sku_id}::#{variant_value}"
end
