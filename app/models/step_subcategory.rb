class StepSubcategory < ApplicationRecord
  belongs_to :step_category

  scope :ordered, -> { order(:sortorder, :name) }

  def to_s = name
end
