module Catalog
  # Fills in the two things NewStar's product records don't carry but its
  # community-scoped payloads do: whether a product has ever actually been sold,
  # and the human-readable names for its category codes.
  #
  # Runs after the per-community sync, since it reads what those syncers wrote.
  class SkuEnricher
    def self.call(...) = new(...).call

    # sellable: only recomputed when the run actually fetched lot selections.
    # The interactive "Refresh SKUs" deliberately skips them (one API call per
    # lot, thousands of lots), so a run that didn't read selections must leave
    # the flag as it found it rather than mark the whole catalog unsold.
    def initialize(fetch_selections:)
      @fetch_selections = fetch_selections
    end

    def call
      backfill_names
      backfill_sellable if @fetch_selections
    end

    private

    # A code seen named anywhere names every SKU sharing it — NewStar is
    # consistent about the code, it just only spells it out on the selection and
    # option payloads.
    def backfill_names
      categories = name_map(:category_code, selection: :category_name, option: :category)
      subcategories = name_map(:subcategory_code, selection: :subcategory_name, option: :subcategory)
      return if categories.empty? && subcategories.empty?

      Sku.find_each do |sku|
        category = categories[sku.category_code]
        subcategory = subcategories[sku.subcategory_code]
        next if category == sku.category_name && subcategory == sku.subcategory_name

        sku.update_columns(category_name: category, subcategory_name: subcategory)
      end
    end

    # The two payloads spell the name column differently — lot selections use
    # `category_name`, options just `category`.
    def name_map(code_column, selection:, option:)
      from_selections = LotSelection.where.not(selection => [ nil, "" ])
        .distinct.pluck(code_column, selection)
      from_options = Option.where.not(option => [ nil, "" ])
        .distinct.pluck(code_column, option)

      # Selections win: they are the more specific, per-home naming.
      (from_options + from_selections).to_h.except(nil, "")
    end

    # "Sold" means the product appears in a real home's configured selections.
    # Written in bulk: this touches every row and the catalog is ~2k.
    def backfill_sellable
      sold = LotSelection.distinct.pluck(:product_code).compact_blank
      return if sold.empty? # nothing fetched after all — leave the flag alone

      Sku.where(product_code: sold).update_all(sellable: true)
      Sku.where.not(product_code: sold).update_all(sellable: false)
      Rails.logger.info({ event: "catalog.sellable_backfilled", sold: sold.size }.to_json)
    end
  end
end
