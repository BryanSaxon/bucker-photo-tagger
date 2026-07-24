class Lot < ApplicationRecord
  # A physical lot in a community. The link to a model is best-effort: the API
  # only gives a free-text model_description, so floorplan may be nil.
  belongs_to :community
  belongs_to :floorplan, optional: true
  has_many :lot_selections, dependent: :destroy

  validates :lot, presence: true, uniqueness: { scope: :community_id }

  scope :ordered, -> { order(:lot) }

  def to_s = lot
end
