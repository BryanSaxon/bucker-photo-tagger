class Sku < ApplicationRecord
  has_many :photo_skus, dependent: :destroy
  has_many :photos, through: :photo_skus

  validates :product_code, presence: true, uniqueness: { case_sensitive: false }

  scope :ordered, -> { order(:short_description, :product_code) }

  # Free-text search across the fields the source catalog actually provides:
  # the product code, its description, and its category/subcategory codes.
  # (The API has no manufacturer or price on the product record.)
  scope :search, ->(query) {
    term = query.to_s.strip
    next all if term.blank?

    like = "%#{sanitize_sql_like(term)}%"
    where(
      "product_code ILIKE :q OR short_description ILIKE :q OR " \
      "category_code ILIKE :q OR subcategory_code ILIKE :q OR attribute1_desc ILIKE :q",
      q: like
    )
  }

  scope :in_category, ->(code) { code.present? ? where(category_code: code) : all }

  # The source catalog has no true "name" — fall back to the code when the
  # short description is blank.
  def display_name
    short_description.presence || product_code
  end

  def to_s = display_name

  # Available variant choices (the API stores them as a CSV in attribute1).
  def attribute_choices
    attribute1.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # Distinct category codes present in the catalog, for filter dropdowns.
  def self.category_codes
    where.not(category_code: [ nil, "" ]).distinct.order(:category_code).pluck(:category_code)
  end
end
