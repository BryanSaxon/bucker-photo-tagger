class Sku < ApplicationRecord
  has_many :photo_skus, dependent: :destroy
  has_many :photos, through: :photo_skus

  # The full set of image records the NewStart catalog lists for this product
  # (metadata only — the API serves no image bytes). Kept in sync from
  # /product_images by Skus::SyncService, keyed by product_code.
  has_many :sku_images, dependent: :destroy

  # Where this product appears in the community catalog (best-effort links from
  # the community-scoped endpoints, resolved by product_code).
  has_many :options, dependent: :nullify
  has_many :lot_selections, dependent: :nullify

  validates :product_code, presence: true, uniqueness: { case_sensitive: false }

  scope :ordered, -> { order(:short_description, :product_code) }

  # Columns the source catalog actually provides. attribute1 holds the variant
  # choices themselves ("Matte Black,Chrome,…") — without it, searching for a
  # finish matches nothing, which is why "white mirror" never surfaced the
  # round/square options. (The API has no manufacturer or price on a product.)
  SEARCH_COLUMNS = %w[
    product_code short_description category_code subcategory_code
    attribute1_desc attribute1
  ].freeze

  # Every term must match somewhere, though not necessarily the same column, so
  # "white mirror" finds a mirror whose variants include white. A single ILIKE
  # over the whole query only ever matched terms that were adjacent in one
  # column, which is the shape designers actually type.
  scope :search, ->(query) {
    terms = query.to_s.split(/\s+/).reject(&:blank?).first(6)
    next all if terms.empty?

    predicate = SEARCH_COLUMNS.map { |column| "skus.#{column} ILIKE :q" }.join(" OR ")
    terms.reduce(all) { |scope, term| scope.where(predicate, q: "%#{sanitize_sql_like(term)}%") }
  }

  scope :in_category, ->(code) { code.present? ? where(category_code: code) : all }

  # Narrow to the products actually available for a photo's captured context,
  # to speed up tagging. A room (the most specific) limits to products selected
  # in that room across the community's lots; a community limits to products in
  # its priced options or any lot selection. With neither, returns everything.
  scope :for_context, ->(community_id: nil, room_id: nil) {
    if room_id.present?
      selected = LotSelection.where(room_id: room_id).where.not(sku_id: nil).select(:sku_id)
      where(id: selected)
    elsif community_id.present?
      opted = Option.where(community_id: community_id).where.not(sku_id: nil).select(:sku_id)
      selected = LotSelection.joins(:lot).where(lots: { community_id: community_id })
        .where.not(sku_id: nil).select(:sku_id)
      where(id: opted).or(where(id: selected))
    else
      all
    end
  }

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

  def variants? = attribute_choices.any?

  # The axis label the catalog uses for this product's variants ("Color",
  # "Finish", "Size"). The source marks required attributes with a trailing
  # "**", which is noise in a form label.
  def variant_label
    attribute1_desc.presence&.delete_suffix("**")&.strip.presence
  end

  # How many photos record each finish for this product — "where is the matte
  # black one installed?", which is the point of tagging variants at all.
  def tagged_variants
    photo_skus.with_variant.group(:variant_value).count
  end

  # Does the source catalog have an image on file for this SKU? (Metadata only —
  # the API exposes no downloadable image bytes in this deployment.)
  def image?
    image_filename.present?
  end

  # Distinct category codes present in the catalog, for filter dropdowns.
  def self.category_codes
    where.not(category_code: [ nil, "" ]).distinct.order(:category_code).pluck(:category_code)
  end
end
