class Room < ApplicationRecord
  # A community-wide area dictionary entry (room_code => room_desc), sourced from
  # the inline `rooms` list on the models2 endpoint.
  belongs_to :community
  # Which designer-facing room type this catalog code represents, assigned by
  # Rooms::Classifier during a sync.
  belongs_to :room_type, optional: true
  has_many :lot_selections, dependent: :nullify
  has_many :photos, dependent: :nullify

  validates :room_code, presence: true, uniqueness: { scope: :community_id }

  def to_s = room_desc.presence || room_code
end
