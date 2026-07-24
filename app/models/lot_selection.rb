class LotSelection < ApplicationRecord
  # One configured option on a lot, from the lot-detail endpoint's
  # selected_drawn_options / selected_design_options arrays. sku and room are
  # resolved best-effort from product_code / room_code and may be nil.
  belongs_to :lot
  belongs_to :sku, optional: true
  belongs_to :room, optional: true

  # Which of the lot's two selection lists this row came from.
  KINDS = %w[drawn design].freeze
  validates :kind, inclusion: { in: KINDS }

  scope :drawn, -> { where(kind: "drawn") }
  scope :design, -> { where(kind: "design") }
end
