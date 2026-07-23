class Community < ApplicationRecord
  has_many :floorplans, dependent: :destroy
  has_many :photos, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:name) }

  def to_s = name
end
