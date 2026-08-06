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
