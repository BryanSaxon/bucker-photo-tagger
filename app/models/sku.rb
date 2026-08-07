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

  # ---- Taggable set -------------------------------------------------------
  #
  # The source catalog is an ERP price list, so it carries rows that can never
  # appear in a photograph: unsellable and contract lines, budget allowances,
  # and "intersecting option" bookkeeping entries. Excluded from the product
  # payload alone, so this needs no stored column.
  NON_PHOTOGRAPHABLE_CATEGORIES = %w[99Unsell 00Contra].freeze
  NON_PHOTOGRAPHABLE_PATTERNS = [ "%allowance%", "Intersecting Option%" ].freeze

  # NULL-safe by construction: `where.not(column: [...])` compiles to NOT IN,
  # which is false rather than true for NULL, so a SKU with no category code
  # would be silently dropped from the taggable set entirely. Exclusions have to
  # opt rows out explicitly, never by failing to match.
  scope :photographable, -> {
    patterns = NON_PHOTOGRAPHABLE_PATTERNS.map { "skus.short_description ILIKE ?" }.join(" OR ")
    where("skus.category_code IS NULL OR skus.category_code NOT IN (?)",
      NON_PHOTOGRAPHABLE_CATEGORIES)
      .where("skus.short_description IS NULL OR NOT (#{patterns})", *NON_PHOTOGRAPHABLE_PATTERNS)
  }

  # What a designer is offered when tagging: real products that have actually
  # been sold in a home.
  #
  # Fails open. If nothing is marked sellable — a database that has never run a
  # full sync, or one whose selections were pruned — this returns the whole
  # photographable catalog rather than an empty picker, which would look like
  # the tool is broken rather than like a filter is on.
  scope :taggable, -> {
    base = photographable
    exists?(sellable: true) ? base.where(sellable: true) : base
  }

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

  # ---- Read-time grouping -------------------------------------------------
  #
  # The price list carries one row per priceable line item, so a single visual
  # thing appears many times: "Arbor Specialty Painted" is 43 rows differing
  # only by a code suffix that encodes a cabinet width or a bath number. A
  # designer tagging a photograph is choosing the visual thing, not the line
  # item, so the list is collapsed on the way out.
  #
  # Derived rather than stored: the key is three columns a SKU already has, so
  # there is no second identity to keep stable across a full-replace sync and
  # no tag migration. Promote it to a table only when something needs to hang
  # off a group.
  #
  # Keyed on category + subcategory as well as the description, because 101
  # descriptions span more than one category and would otherwise merge
  # genuinely different products. Normalised so trailing whitespace or case
  # drift upstream doesn't split one group into two.
  GROUP_KEY_COLUMNS = %i[category_code subcategory_code short_description].freeze

  def self.normalize_for_key(value)
    value.to_s.strip.gsub(/\s+/, " ").downcase.presence || "-"
  end

  def group_key
    self.class.group_key_for(category_code, subcategory_code, short_description)
  end

  def self.group_key_for(*parts)
    parts.map { |part| normalize_for_key(part) }.join("")
  end

  # SQL expression for the same key, so grouping can happen in the database.
  def self.group_key_sql
    GROUP_KEY_COLUMNS
      .map { |c| "COALESCE(NULLIF(BTRIM(REGEXP_REPLACE(LOWER(skus.#{c}), '\\s+', ' ', 'g')), ''), '-')" }
      .join(" || CHR(1) || ")
  end

  # One representative row per group. MIN(id) keeps the choice deterministic,
  # so the same search returns the same row every time.
  scope :representatives, -> {
    where(id: unscope(:select).select("MIN(skus.id)").group(Arel.sql(group_key_sql)))
  }

  # group_key => number of rows collapsed into it, for the scope given.
  def self.group_sizes(scope = all)
    scope.unscope(:select, :order)
      .group(Arel.sql(group_key_sql))
      .count
  end

  # The other line items that collapse into this row.
  def group_siblings
    self.class.where(category_code: category_code, subcategory_code: subcategory_code,
      short_description: short_description).where.not(id: id)
  end

  # Choices across every member of the group. Members usually agree exactly
  # (223 of 239 multi-member groups), but where they differ the union is what
  # the designer can actually have.
  def grouped_attribute_choices
    (attribute_choices + group_siblings.pluck(:attribute1).flat_map { |a|
      a.to_s.split(",").map(&:strip)
    }).reject(&:blank?).uniq
  end

  # The source catalog has no true "name" — fall back to the code when the
  # short description is blank.
  def display_name
    short_description.presence || product_code
  end

  # Prefer the human category name where the sync found one; the code is all
  # NewStar puts on a product record.
  def category_label = category_name.presence || category_code
  def subcategory_label = subcategory_name.presence || subcategory_code

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
