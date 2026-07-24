class Floorplan < ApplicationRecord
  # Floorplan is the API's "Model": a model (name) + elevation offered in a
  # community, enriched from the models2 endpoint.
  belongs_to :community
  has_many :photos, dependent: :nullify
  # Best-effort links: lots and options reference a model only by free text.
  has_many :lots, dependent: :nullify
  has_many :options, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:name, :elevation) }
  scope :sellable, -> { where(sellable: true, discontinued: false) }

  # The comma-joined room_code list is stored as text; expose it as an array.
  def base_room_codes
    base_model_rooms.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # e.g. "Abigail 1A" — mirrors the API's model_description (model + elevation).
  def display_name
    [ name, elevation ].compact_blank.join(" ")
  end

  def to_s = display_name
end
