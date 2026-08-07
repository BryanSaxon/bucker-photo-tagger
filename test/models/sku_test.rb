require "test_helper"

class SkuTest < ActiveSupport::TestCase
  test "requires a product_code" do
    assert_not Sku.new.valid?
  end

  test "product_code is unique case-insensitively" do
    Sku.create!(product_code: "ABC123")
    dup = Sku.new(product_code: "abc123")
    assert_not dup.valid?
  end

  test "search matches code, description and category" do
    sku = Sku.create!(product_code: "FLRLVP7", short_description: "Luxury Vinyl Plank", category_code: "05FlrTil")

    assert_includes Sku.search("flrlvp"), sku
    assert_includes Sku.search("vinyl"), sku
    assert_includes Sku.search("05flr"), sku
    assert_not_includes Sku.search("nonexistent"), sku
  end

  test "blank search returns all" do
    Sku.create!(product_code: "X1")
    assert_equal Sku.count, Sku.search("").count
  end

  test "display_name falls back to product_code" do
    assert_equal "CODE1", Sku.new(product_code: "CODE1").display_name
    assert_equal "A Sink", Sku.new(product_code: "C", short_description: "A Sink").display_name
  end

  test "attribute_choices splits the CSV" do
    sku = Sku.new(attribute1: "White, Espresso ,Natural Oak")
    assert_equal %w[White Espresso Natural\ Oak].map(&:strip), sku.attribute_choices
  end

  # ---- Variant-aware search ----

  test "search matches a variant choice, not just the axis label" do
    mirror = Sku.create!(product_code: "MIR1", short_description: "Framed Mirror",
      attribute1_desc: "Shape**", attribute1: "Round,Square")

    assert_includes Sku.search("round"), mirror
    assert_includes Sku.search("square"), mirror
  end

  # Ben's report: she searched "white mirror" and the round/square variants
  # never surfaced. Each term may match a different column.
  test "search spans columns across terms so 'white mirror' finds a white mirror" do
    mirror = Sku.create!(product_code: "MIR2", short_description: "Framed Mirror",
      attribute1_desc: "Color**", attribute1: "White,Black")

    assert_includes Sku.search("white mirror"), mirror
    assert_includes Sku.search("mirror white"), mirror
  end

  test "search requires every term to match somewhere" do
    mirror = Sku.create!(product_code: "MIR3", short_description: "Framed Mirror",
      attribute1: "White,Black")

    assert_not_includes Sku.search("white nonexistent"), mirror
  end

  test "search finds a multi-word finish inside the choice list" do
    faucet = Sku.create!(product_code: "FCT1", short_description: "Kitchen Faucet",
      attribute1_desc: "Finish**", attribute1: "Matte Black,Brushed Nickel")

    assert_includes Sku.search("matte black"), faucet
    assert_includes Sku.search("black faucet"), faucet
  end

  test "variant_label strips the required-marker suffix" do
    assert_equal "Finish", Sku.new(attribute1_desc: "Finish**").variant_label
    assert_equal "Color", Sku.new(attribute1_desc: "Color").variant_label
    assert_nil Sku.new(attribute1_desc: "").variant_label
  end

  test "variants? reflects whether the catalog offers choices" do
    assert Sku.new(attribute1: "Round,Square").variants?
    assert_not Sku.new(attribute1: "").variants?
    assert_not Sku.new.variants?
  end

  # ---- Taggable set ----

  test "unsellable and contract lines are never offered for tagging" do
    junk = Sku.create!(product_code: "X1", short_description: "Hood Insert", category_code: "99Unsell")
    real = Sku.create!(product_code: "X2", short_description: "Kitchen Faucet", category_code: "04Plumbi")

    assert_not_includes Sku.photographable, junk
    assert_includes Sku.photographable, real
  end

  test "allowances and bookkeeping entries are never offered for tagging" do
    allowance = Sku.create!(product_code: "X3", short_description: "Lighting Allowance for One Story Homes")
    crossing = Sku.create!(product_code: "X4", short_description: "Intersecting Option - DOBONUS1 & DOCORNER")

    assert_not_includes Sku.photographable, allowance
    assert_not_includes Sku.photographable, crossing
  end

  # NOT IN is false for NULL, so an exclusion written the obvious way drops
  # every SKU with no category — the opposite of what it should do.
  test "a sku with no category or description is still taggable" do
    bare = Sku.create!(product_code: "X5")

    assert_includes Sku.photographable, bare
  end

  test "taggable narrows to what has been sold" do
    sold = Sku.create!(product_code: "X6", short_description: "Sold Faucet", sellable: true)
    unsold = Sku.create!(product_code: "X7", short_description: "Unsold Faucet", sellable: false)

    assert_includes Sku.taggable, sold
    assert_not_includes Sku.taggable, unsold
  end

  # A filter that hides the entire catalog looks like a broken tool, so an
  # empty sold-set falls back to offering everything.
  test "taggable fails open when nothing is marked sellable" do
    Sku.create!(product_code: "X8", short_description: "Faucet", sellable: false)
    Sku.update_all(sellable: false)

    assert_equal Sku.photographable.count, Sku.taggable.count
    assert_predicate Sku.taggable.count, :positive?
  end

  # ---- Read-time grouping ----

  test "line items differing only by code collapse to one entry" do
    3.times { |i| Sku.create!(product_code: "CAB#{i}", short_description: "Arbor Painted",
      category_code: "07CabTop", subcategory_code: "12Cabs") }

    reps = Sku.where(short_description: "Arbor Painted").representatives
    assert_equal 1, reps.count
    assert_equal 3, Sku.group_sizes(Sku.where(short_description: "Arbor Painted")).values.sum
  end

  # 101 descriptions span more than one category; grouping on description alone
  # would merge genuinely different products.
  test "the same description in different categories stays separate" do
    Sku.create!(product_code: "A1", short_description: "Arbor Painted",
      category_code: "07CabTop", subcategory_code: "12Cabs")
    Sku.create!(product_code: "A2", short_description: "Arbor Painted",
      category_code: "07CabTop", subcategory_code: "12CabsI")

    assert_equal 2, Sku.where(short_description: "Arbor Painted").representatives.count
  end

  test "whitespace and case drift does not split a group" do
    a = Sku.create!(product_code: "B1", short_description: "Arbor  Painted", category_code: "07CabTop")
    b = Sku.create!(product_code: "B2", short_description: "arbor painted", category_code: "07CabTop")

    assert_equal a.group_key, b.group_key
    assert_equal 1, Sku.where(id: [ a.id, b.id ]).representatives.count
  end

  test "the representative is stable across queries" do
    3.times { |i| Sku.create!(product_code: "C#{i}", short_description: "Beams", category_code: "08Trim") }
    scope = Sku.where(short_description: "Beams")

    assert_equal scope.representatives.pluck(:id), scope.representatives.pluck(:id)
  end

  test "variant choices are the union across the group" do
    a = Sku.create!(product_code: "D1", short_description: "Faucet", category_code: "04Plumbi",
      attribute1: "Chrome,Matte Black")
    Sku.create!(product_code: "D2", short_description: "Faucet", category_code: "04Plumbi",
      attribute1: "Chrome,Brushed Nickel")

    assert_equal %w[Brushed\ Nickel Chrome Matte\ Black], a.grouped_attribute_choices.sort
  end

  test "category_label prefers the human name and falls back to the code" do
    named = Sku.new(category_code: "05FlrTil", category_name: "Flooring & Wall Tile")
    unnamed = Sku.new(category_code: "05FlrTil")

    assert_equal "Flooring & Wall Tile", named.category_label
    assert_equal "05FlrTil", unnamed.category_label
  end

  test "tagged_variants counts photos per recorded finish" do
    sku = Sku.create!(product_code: "FCT2", attribute1: "Chrome,Matte Black")
    3.times do |i|
      photo = Photo.new(name: "shot-#{i}")
      photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
      photo.save!
      PhotoSku.create!(photo: photo, sku: sku, variant_value: i < 2 ? "Chrome" : "Matte Black")
      PhotoSku.create!(photo: photo, sku: sku) if i == 2 # no finish recorded — excluded
    end

    assert_equal({ "Chrome" => 2, "Matte Black" => 1 }, sku.tagged_variants)
  end
end
