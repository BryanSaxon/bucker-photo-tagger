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
end
