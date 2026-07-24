module Catalog
  # Full-replaces a community's priced options from /options. Each option is
  # linked to a product by product_code and to a model by model + elev
  # (best-effort; either may be nil). Because there is no stable natural key, the
  # community's options are deleted and re-inserted each run.
  class OptionsSyncer
    def self.call(community, options, **opts)
      new(community, options, **opts).call
    end

    def initialize(community, options)
      @community = community
      @options = options || []
    end

    # Returns the number of options written.
    def call
      sku_ids = Sku.pluck(:product_code, :id).to_h
      floorplan_ids = @community.floorplans.pluck(:name, :elevation, :id)
        .to_h { |name, elev, id| [ [ name, elev ], id ] }
      now = Time.current

      rows = @options.filter_map do |o|
        code = o["product_code"].presence
        rules = o["room_replacement_rules"] || {}
        {
          community_id: @community.id,
          sku_id: code && sku_ids[code],
          floorplan_id: floorplan_ids[[ o["model"], o["elev"] ]],
          product_code: code,
          model: o["model"],
          elev: o["elev"],
          model_description: o["model_description"],
          description: o["description"],
          short_description: o["short_description"],
          category: o["category"],
          category_code: o["category_code"],
          subcategory: o["subcategory"],
          subcategory_code: o["subcategory_code"],
          option_type: o["option_type"],
          unit_price: Casts.decimal(o["unit_price"]),
          qty: Casts.decimal(o["qty"]),
          uofm: o["uofm"],
          gross_sale: Casts.decimal(o["gross_sale"]),
          add_floor_area: o["add_floor_area"],
          room_replacement_add: rules["add_rooms"],
          room_replacement_remove: rules["remove_rooms"],
          source_modified_at: o["moddatetime"],
          created_at: now,
          updated_at: now
        }
      end

      Option.transaction do
        @community.options.delete_all
        rows.each_slice(500) { |batch| Option.insert_all(batch) } if rows.any?
      end
      rows.size
    end
  end
end
