namespace :catalog do
  desc "Derive sellable flags and category names from data already in the database"
  task enrich: :environment do
    before = Sku.where(sellable: true).count
    Catalog::SkuEnricher.call(fetch_selections: LotSelection.exists?)
    after = Sku.where(sellable: true).count

    puts "Sellable: #{before} -> #{after} of #{Sku.count}"
    puts "Named:    #{Sku.where.not(category_name: [ nil, '' ]).count} of #{Sku.count}"
    puts "Taggable: #{Sku.taggable.count}, shown as #{Sku.taggable.representatives.count} entries"
  end

  # Everything a deploy of this branch needs on an existing database. Reads only
  # what has already been synced, so it needs no NewStar credentials and can run
  # immediately rather than waiting for the next full catalog sync.
  desc "Post-deploy backfill: room types, catalog names, sellable flags"
  task backfill: :environment do
    Rake::Task["room_types:backfill"].invoke
    Rake::Task["catalog:enrich"].invoke
  end
end
