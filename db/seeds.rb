# Idempotent seed data for Photo Tagger.
#
# Communities and floorplans mirror examples from the NewStart field guide.
# SKUs are NOT seeded — they are synced from the live NewStart catalog via the
# SKU Library ("Refresh SKUs from API"), so the catalog stays an exact mirror of
# the source instead of accumulating placeholder data.

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
puts "SKUs: sync from the SKU Library (Refresh SKUs from API)."
