# Idempotent seed data for Photo Tagger.
#
# Communities and floorplans mirror examples from the NewStart field guide.
# Sample SKUs stand in for a live API sync so the app is fully usable out of the
# box — run a real sync from the SKU Library once API credentials are configured.

# ---- Login user ----------------------------------------------------------
user = User.find_or_initialize_by(email_address: "accounts@bryansaxon.com")
user.password = "password"
user.save!
puts "Seed user: #{user.email_address} / password"

# ---- Communities & floorplans -------------------------------------------
communities = {
  "1682" => "Bradbury at Blackridge",
  "1684" => "Blackridge Phase 2-6",
  "1760" => "Mills Creek"
}

floorplans_by_community = {
  "1682" => [ [ "Abigail", "1A" ], [ "Abigail", "1B" ], [ "Hartley", "2B" ], [ "Addington", "1C" ] ],
  "1684" => [ [ "Bexley", "3A" ], [ "Camden", "2C" ] ],
  "1760" => [ [ "Delmar", "1A" ], [ "Everly", "2B" ] ]
}

communities.each do |code, name|
  community = Community.find_or_create_by!(code: code) { |c| c.name = name }
  community.update!(name: name)

  Array(floorplans_by_community[code]).each do |plan_name, elevation|
    Floorplan.find_or_create_by!(community: community, name: plan_name, elevation: elevation)
  end
end
puts "Communities: #{Community.count}, Floorplans: #{Floorplan.count}"

# ---- Sample SKUs ---------------------------------------------------------
# Shaped like the API's Product records: product_code + short_description +
# category/subcategory codes + attribute1 variant CSV.
sample_skus = [
  { product_code: "110FREEZER", short_description: "110 Outlet on a Dedicated Circuit", category_code: "81Electr", subcategory_code: "81Electr", attribute1_desc: "Location**", attribute1: "In Garage,In Basement,Typical Height" },
  { product_code: "DOBARCABS", short_description: "Built-in Home Bar", category_code: "01DrawnO", subcategory_code: "12Cabs", attribute1_desc: "Finish**", attribute1: "White,Espresso,Natural Oak" },
  { product_code: "FPGAS36", short_description: "36\" Direct Vent Gas Fireplace", category_code: "01DrawnO", subcategory_code: "03Firepl", attribute1_desc: "Surround**", attribute1: "Tile,Stone,Shiplap" },
  { product_code: "CTQTZ3CM", short_description: "3cm Quartz Countertop", category_code: "07CabTop", subcategory_code: "07CabTop", attribute1_desc: "Color**", attribute1: "Calacatta,Carrara,Pure White,Charcoal" },
  { product_code: "CABSHAKER", short_description: "Shaker-Style Kitchen Cabinets", category_code: "01DrawnO", subcategory_code: "12Cabs", attribute1_desc: "Finish**", attribute1: "White,Gray,Navy,Espresso" },
  { product_code: "FLRLVP7", short_description: "7\" Luxury Vinyl Plank Flooring", category_code: "05FlrTil", subcategory_code: "05FlrTil", attribute1_desc: "Color**", attribute1: "Weathered Oak,Smoke,Honey,Driftwood" },
  { product_code: "TILSUB3X6", short_description: "3x6 Ceramic Subway Tile Backsplash", category_code: "05FlrTil", subcategory_code: "05FlrTil", attribute1_desc: "Color**", attribute1: "White Gloss,Matte White,Sage" },
  { product_code: "LGTPEND3", short_description: "3-Light Pendant over Island", category_code: "09Lighti", subcategory_code: "81Electr", attribute1_desc: "Finish**", attribute1: "Matte Black,Brushed Nickel,Brass" },
  { product_code: "LGTREC6", short_description: "6\" LED Recessed Can Light", category_code: "09Lighti", subcategory_code: "81Electr", attribute1_desc: "" , attribute1: "" },
  { product_code: "TRIMCRWN", short_description: "Crown Molding Package", category_code: "08Trim", subcategory_code: "08Trim", attribute1_desc: "Profile**", attribute1: "Colonial,Craftsman,Modern" },
  { product_code: "TRIMBASE5", short_description: "5\" Baseboard Trim", category_code: "08Trim", subcategory_code: "08Trim", attribute1_desc: "Style**", attribute1: "Square,Colonial" },
  { product_code: "SINKFARM33", short_description: "33\" Farmhouse Apron Sink", category_code: "07CabTop", subcategory_code: "07CabTop", attribute1_desc: "Material**", attribute1: "Fireclay,Stainless,Cast Iron" },
  { product_code: "FCTPULL", short_description: "Pull-Down Kitchen Faucet", category_code: "07CabTop", subcategory_code: "07CabTop", attribute1_desc: "Finish**", attribute1: "Chrome,Matte Black,Brushed Gold" },
  { product_code: "APPGE5PC", short_description: "GE 5-Piece Stainless Appliance Package", category_code: "01DrawnO", subcategory_code: "04CabApp", attribute1_desc: "Finish**", attribute1: "Stainless,Slate,Black Stainless" },
  { product_code: "DOORINT2P", short_description: "2-Panel Interior Door", category_code: "08Trim", subcategory_code: "02WindDo", attribute1_desc: "Style**", attribute1: "Smooth,Textured" },
  { product_code: "WINBAY", short_description: "Bay Window Upgrade", category_code: "01DrawnO", subcategory_code: "02WindDo", attribute1_desc: "Location**", attribute1: "Breakfast Nook,Primary Bedroom" },
  { product_code: "STAIRIRON", short_description: "Wrought Iron Stair Balusters", category_code: "08Trim", subcategory_code: "08Trim", attribute1_desc: "Finish**", attribute1: "Matte Black,Oil-Rubbed Bronze" },
  { product_code: "MIRRORFRM", short_description: "Framed Vanity Mirror", category_code: "01DrawnO", subcategory_code: "12Cabs", attribute1_desc: "Finish**", attribute1: "White,Espresso,Gold" },
  { product_code: "TILSHWR12", short_description: "12x24 Porcelain Shower Wall Tile", category_code: "05FlrTil", subcategory_code: "05FlrTil", attribute1_desc: "Color**", attribute1: "Marble Look,Concrete Gray,Warm Taupe" },
  { product_code: "VANDBL60", short_description: "60\" Double-Sink Vanity", category_code: "01DrawnO", subcategory_code: "12Cabs", attribute1_desc: "Finish**", attribute1: "White,Gray,Navy" }
]

now = Time.current
rows = sample_skus.map { |s| s.merge(created_at: now, updated_at: now) }
Sku.upsert_all(rows, unique_by: :product_code)
puts "Sample SKUs: #{Sku.count}"
