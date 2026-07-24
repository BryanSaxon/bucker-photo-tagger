class Step < ApplicationRecord
  # A configurator step for a community, ordering the category/subcategory tree.
  # Only display names + sort order are exposed by the API (no category codes).
  belongs_to :community
  has_many :step_categories, dependent: :destroy

  validates :step, presence: true, uniqueness: { scope: :community_id }

  scope :ordered, -> { order(:sortorder, :step) }

  def to_s = step
end
