class SkuImage < ApplicationRecord
  belongs_to :sku

  # The catalog serves two kinds of image record per product (see
  # NewStart /product_images): one "Product" image plus any number of
  # "ProductAttr" images tied to a specific variant.
  PRIMARY_SOURCE_TYPE = "Product".freeze

  validates :file_id, presence: true, uniqueness: true

  scope :live, -> { where(archived: false) }
  # The representative image first: prefer the product-level one, then order
  # variant images stably by their attribute + filename.
  scope :primary_first, -> {
    order(Arel.sql("source_type = #{connection.quote(PRIMARY_SOURCE_TYPE)} DESC"), :attribute1, :filename)
  }

  # Which variant this image depicts, if any (e.g. "Chrome" / "Gray Mortar").
  def variant_label
    [ attribute1, attribute2 ].compact_blank.join(" · ").presence
  end

  # Is this the product-level image rather than a variant-specific one?
  def primary?
    source_type == PRIMARY_SOURCE_TYPE
  end

  def display_title
    title.presence || description.presence || filename.presence || file_id
  end
end
