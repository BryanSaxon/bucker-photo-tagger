class StepCategory < ApplicationRecord
  belongs_to :step
  has_many :step_subcategories, dependent: :destroy

  scope :ordered, -> { order(:sortorder, :name) }

  def to_s = name
end
