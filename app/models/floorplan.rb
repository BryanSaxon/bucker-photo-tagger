class Floorplan < ApplicationRecord
  belongs_to :community
  has_many :photos, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:name, :elevation) }

  # e.g. "Abigail 1A" — mirrors the API's model_description (model + elevation).
  def display_name
    [ name, elevation ].compact_blank.join(" ")
  end

  def to_s = display_name
end
