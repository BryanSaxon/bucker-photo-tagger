class RoomType < ApplicationRecord
  # The designer-facing room vocabulary — global, not per community, so "every
  # master bath" is answerable across the whole library. The NewStart room
  # dictionary (Room) stays alongside it as an optional, more precise refinement.
  has_many :rooms, dependent: :nullify
  has_many :photos, dependent: :nullify

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  scope :ordered, -> { order(:sort_order, :name) }
  scope :available, -> { where(active: true) }

  def to_s = name

  # Load (or top up) the vocabulary from config/room_types.yml. Idempotent, and
  # deliberately does not overwrite a name or ordering staff have edited in the
  # app — the file seeds the list, Signature owns it afterwards.
  def self.load_vocabulary!
    YAML.load_file(Rails.root.join("config/room_types.yml")).each do |attrs|
      next if exists?(key: attrs["key"])

      create!(key: attrs["key"], name: attrs["name"], sort_order: attrs["sort_order"] || 0)
    end
  end
end
