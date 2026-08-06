class Photo < ApplicationRecord
  # Processing lifecycle. New uploads start as :unprocessed and become
  # :complete once a processor saves their community/floorplan/SKU selections.
  enum :status, { unprocessed: 0, complete: 1 }, default: :unprocessed

  # Optional catalog context captured at upload (or during processing): which
  # community / model (floorplan) / room the photo depicts. Stored so it can
  # narrow product selection when the photo is processed.
  belongs_to :community, optional: true
  belongs_to :floorplan, optional: true
  belongs_to :room, optional: true
  belongs_to :processed_by, class_name: "User", optional: true

  has_many :photo_skus, dependent: :destroy
  has_many :skus, through: :photo_skus

  # A resized :thumb variant for grid thumbnails — full-size images are far too
  # heavy to list. preprocessed so new uploads generate it up front (existing
  # photos generate it on first view, then it's cached).
  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 600, 600 ], preprocessed: true
  end

  accepts_nested_attributes_for :photo_skus, allow_destroy: true

  validates :name, presence: true
  validate :image_must_be_attached
  validate :context_is_consistent

  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(query) {
    term = query.to_s.strip
    term.present? ? where("name ILIKE ?", "%#{sanitize_sql_like(term)}%") : all
  }

  # Photos carrying a tag with no finish recorded against a product that offers
  # choices — the re-visit queue for work tagged before variants existed.
  # Adding the missing finish keeps the hand-placed pins, unlike re-tagging.
  scope :missing_variants, -> {
    where(
      "EXISTS (SELECT 1 FROM photo_skus ps JOIN skus s ON s.id = ps.sku_id " \
      "WHERE ps.photo_id = photos.id AND ps.variant_value = '' " \
      "AND s.attribute1 IS NOT NULL AND s.attribute1 <> '')"
    )
  }

  # Persist the processor's selections and mark the photo complete.
  def mark_complete!(user)
    update!(status: :complete, processed_by: user, processed_at: Time.current)
  end

  private

  def image_must_be_attached
    errors.add(:image, "must be attached") unless image.attached?
  end

  # A chosen floorplan/room must belong to the chosen community. (The upload
  # flow back-fills community from a lone floorplan/room before saving, so this
  # only trips on genuinely mismatched combinations.)
  def context_is_consistent
    if floorplan && community && floorplan.community_id != community_id
      errors.add(:floorplan, "is not in the selected community")
    end
    if room && community && room.community_id != community_id
      errors.add(:room, "is not in the selected community")
    end
  end
end
