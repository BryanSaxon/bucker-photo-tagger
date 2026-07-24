module Catalog
  # Upserts the community list (the root of the object graph) from /communities,
  # keyed by project_code (stored as Community#code). Prunes communities that
  # left the catalog unless they are referenced by photos.
  class CommunitiesSyncer
    def self.call(client: Newstart::Client.new)
      new(client).call
    end

    def initialize(client)
      @client = client
    end

    # Returns the number of communities upserted.
    def call
      communities = @client.communities
      return 0 if communities.blank?

      now = Time.current
      rows = communities.filter_map do |c|
        code = c["project_code"].presence
        next unless code

        {
          code: code,
          name: c["name"].presence || code,
          product_library_code: c["product_library_code"],
          created_at: now,
          updated_at: now
        }
      end
      rows.uniq! { |r| r[:code] }

      Community.upsert_all(rows, unique_by: :code, update_only: %i[name product_library_code]) if rows.any?
      prune(rows)
      rows.size
    end

    private

    def prune(rows)
      codes = rows.map { |r| r[:code] }
      return if codes.empty?

      # destroy_all (not delete_all) so dependent floorplans/rooms/lots/options/
      # steps are removed and photos are nullified. Communities with photos stay.
      stale = Community.where.not(code: codes).where.missing(:photos)
      count = stale.count
      stale.destroy_all
      Rails.logger.info("[Catalog::CommunitiesSyncer] pruned #{count} stale communities") if count.positive?
    end
  end
end
