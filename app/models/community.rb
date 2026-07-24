class Community < ApplicationRecord
  # The API's project_code is stored as `code`.
  has_many :floorplans, dependent: :destroy
  has_many :rooms, dependent: :destroy
  has_many :lots, dependent: :destroy
  has_many :options, dependent: :destroy
  has_many :steps, dependent: :destroy
  has_many :photos, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:name) }

  def to_s = name
end
