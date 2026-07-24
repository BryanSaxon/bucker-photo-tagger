module Catalog
  # Orchestrates a full replica sync of the NewStar catalog onto the local data
  # model, recording progress/outcome on a SkuSync record.
  #
  # Order matters: products (and their images) are synced first so the
  # community-scoped rows (options, lot selections) can resolve product_code to a
  # Sku. Then, per community, models (+ rooms) are synced before lots and options
  # so those can resolve their model/room links.
  #
  # Each community is synced independently: one community's failure is logged and
  # skipped so it can't abort the whole run. Options let a caller scope the run to
  # a single community and cap per-lot selection fetching (which costs one API
  # call per lot) — used for fast verification.
  class SyncService
    def self.call(sku_sync, client: Newstart::Client.new, only_community: nil,
                  fetch_selections: true, lot_limit: nil)
      new(sku_sync, client, only_community, fetch_selections, lot_limit).call
    end

    def initialize(sku_sync, client, only_community, fetch_selections, lot_limit)
      @sku_sync = sku_sync
      @client = client
      @only_community = only_community
      @fetch_selections = fetch_selections
      @lot_limit = lot_limit
    end

    def call
      @sku_sync.update!(status: :running, started_at: Time.current)

      product_count = ProductsSyncer.call(client: @client)
      CommunitiesSyncer.call(client: @client)
      communities.each { |community| sync_community(community) }

      @sku_sync.mark_completed!(product_count)
      @sku_sync
    rescue => e
      Rails.logger.error("[Catalog::SyncService] #{e.class}: #{e.message}")
      @sku_sync.mark_failed!("#{e.class}: #{e.message}")
      @sku_sync
    end

    private

    def communities
      scope = Community.all
      scope = scope.where(code: @only_community) if @only_community
      scope
    end

    def sync_community(community)
      code = community.code
      ModelsSyncer.call(community, @client.community_models(code))
      LotsSyncer.call(community, @client.community_lots(code), client: @client,
        fetch_selections: @fetch_selections, lot_limit: @lot_limit)
      OptionsSyncer.call(community, @client.community_options(code))
      StepsSyncer.call(community, @client.community_steps(code))
    rescue => e
      # One community's failure (e.g. a 500 on a sub-endpoint) must not abort the
      # whole sync.
      Rails.logger.warn("[Catalog::SyncService] community #{community.code} failed: #{e.class}: #{e.message}")
    end
  end
end
