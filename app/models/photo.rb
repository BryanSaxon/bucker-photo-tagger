class Photo < ApplicationRecord
  # Processing lifecycle. New uploads start as :unprocessed and become
  # :complete once a processor saves their community/floorplan/SKU selections.
  enum :status, { unprocessed: 0, complete: 1 }, default: :unprocessed

  belongs_to :community, optional: true
  belongs_to :floorplan, optional: true
  belongs_to :processed_by, class_name: "User", optional: true

  has_many :photo_skus, dependent: :destroy
  has_many :skus, through: :photo_skus

  has_one_attached :image

  accepts_nested_attributes_for :photo_skus, allow_destroy: true

  validates :name, presence: true
  validate :image_must_be_attached

  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(query) {
    term = query.to_s.strip
    term.present? ? where("name ILIKE ?", "%#{sanitize_sql_like(term)}%") : all
  }

  # Persist the processor's selections and mark the photo complete.
  def mark_complete!(user)
    update!(status: :complete, processed_by: user, processed_at: Time.current)
  end

  private

  def image_must_be_attached
    errors.add(:image, "must be attached") unless image.attached?
  end
end
