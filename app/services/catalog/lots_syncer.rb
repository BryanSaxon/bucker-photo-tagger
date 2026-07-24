module Catalog
  # Upserts a community's lots from /lots, and (optionally) each lot's configured
  # selections from the per-lot detail endpoint. Lots link to a model only by
  # free-text model_description (best-effort). Selections are full-replaced per
  # lot and resolve product_code -> Sku and room_code -> Room where possible.
  #
  # Fetching selections costs one API call per lot, so callers can cap how many
  # lots get detail (lot_limit) or skip detail entirely (fetch_selections: false).
  class LotsSyncer
    def self.call(community, lots, client:, fetch_selections: true, lot_limit: nil)
      new(community, lots, client, fetch_selections, lot_limit).call
    end

    def initialize(community, lots, client, fetch_selections, lot_limit)
      @community = community
      @lots = lots || []
      @client = client
      @fetch_selections = fetch_selections
      @lot_limit = lot_limit
    end

    # Returns the number of lots upserted.
    def call
      count = sync_lots
      sync_selections if @fetch_selections
      count
    end

    private

    def sync_lots
      floorplan_ids = @community.floorplans.where.not(model_description: nil)
        .pluck(:model_description, :id).to_h
      now = Time.current

      rows = @lots.filter_map do |l|
        number = l["lot"].presence
        next unless number

        {
          community_id: @community.id,
          floorplan_id: floorplan_ids[l["model_description"]],
          lot: number,
          lot_address: l["lot_address"],
          lot_status: l["lot_status"],
          lot_type: l["lot_type"],
          model_description: l["model_description"],
          base_model_price: Casts.decimal(l["base_model_price"]),
          lot_price: Casts.decimal(l["lot_price"]),
          lot_premium: Casts.decimal(l["lot_premium"]),
          gross_sale: Casts.decimal(l["gross_sale"]),
          options_total: Casts.decimal(l["options"]),
          created_at: now,
          updated_at: now
        }
      end
      rows.uniq! { |r| r[:lot] }

      if rows.any?
        rows.each_slice(500) do |batch|
          Lot.upsert_all(batch, unique_by: :index_lots_on_community_id_and_lot,
            update_only: %i[floorplan_id lot_address lot_status lot_type model_description
                            base_model_price lot_price lot_premium gross_sale options_total])
        end
      end
      @community.lots.where.not(lot: rows.map { |r| r[:lot] }).delete_all if rows.any?
      rows.size
    end

    def sync_selections
      sku_ids = Sku.pluck(:product_code, :id).to_h
      room_ids = @community.rooms.pluck(:room_code, :id).to_h

      lots = @community.lots.order(:lot)
      lots = lots.limit(@lot_limit) if @lot_limit
      lots.each do |lot|
        detail = @client.community_lot(@community.code, lot.lot)
        next unless detail

        rows = selection_rows(detail, lot, sku_ids, room_ids)
        LotSelection.transaction do
          lot.lot_selections.delete_all
          rows.each_slice(500) { |batch| LotSelection.insert_all(batch) } if rows.any?
        end
      rescue Newstart::Client::RequestError => e
        Rails.logger.warn("[Catalog::LotsSyncer] lot #{lot.lot} detail failed: #{e.message}")
      end
    end

    def selection_rows(detail, lot, sku_ids, room_ids)
      now = Time.current
      {
        "drawn" => detail["selected_drawn_options"],
        "design" => detail["selected_design_options"]
      }.flat_map do |kind, selections|
        Array(selections).map do |s|
          code = s["product_code"].presence
          room_code = s["room_code"].presence
          {
            lot_id: lot.id,
            sku_id: code && sku_ids[code],
            room_id: room_code && room_ids[room_code],
            kind: kind,
            product_code: code,
            product_description: s["product_description"],
            short_description: s["short_description"],
            attribute1_desc: s["attribute1_desc"],
            attribute1: s["attribute1"],
            attribute2_desc: s["attribute2_desc"],
            attribute2: s["attribute2"],
            model_description: s["model_description"],
            category_code: s["category_code"],
            category_name: s["category_name"],
            subcategory_code: s["subcategory_code"],
            subcategory_name: s["subcategory_name"],
            unit_price: Casts.decimal(s["unit_price"]),
            quantity: Casts.decimal(s["quantity"]),
            uofm: s["uofm"],
            gross_sale: Casts.decimal(s["gross_sale"]),
            room_code: room_code,
            room_description: s["room_description"],
            created_at: now,
            updated_at: now
          }
        end
      end
    end
  end
end
