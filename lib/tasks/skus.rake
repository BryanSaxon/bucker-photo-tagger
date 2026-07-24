namespace :skus do
  desc "Download and attach NewStart product images for SKUs that have image metadata but no bytes yet"
  task backfill_images: :environment do
    attached = Skus::ImageBackfillService.call
    puts "Attached #{attached} image(s)."
  end
end
