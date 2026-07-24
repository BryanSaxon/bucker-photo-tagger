require "test_helper"

class SkuImageTest < ActiveSupport::TestCase
  def sku
    @sku ||= Sku.create!(product_code: "AAA")
  end

  def build(**attrs)
    SkuImage.new({ sku: sku, product_code: "AAA", file_id: "F-1", filename: "AAA.JPG",
                   source_type: "Product" }.merge(attrs))
  end

  test "requires a file_id and enforces uniqueness" do
    build.save!
    dup = build(file_id: "F-1")
    assert_not dup.valid?
    assert_includes dup.errors[:file_id], "has already been taken"
  end

  test "primary? is true only for the Product source_type" do
    assert build(source_type: "Product").primary?
    assert_not build(source_type: "ProductAttr").primary?
  end

  test "variant_label joins the present attributes and is nil when blank" do
    assert_equal "Chrome · Gray", build(attribute1: "Chrome", attribute2: "Gray").variant_label
    assert_equal "Chrome", build(attribute1: "Chrome", attribute2: "").variant_label
    assert_nil build(attribute1: "", attribute2: nil).variant_label
  end

  test "display_title falls back through title, description, filename, file_id" do
    assert_equal "Nice", build(title: "Nice", filename: "x.jpg").display_title
    assert_equal "A desc", build(title: nil, description: "A desc").display_title
    assert_equal "x.jpg", build(title: nil, description: nil, filename: "x.jpg").display_title
    assert_equal "F-9", build(file_id: "F-9", title: nil, description: nil, filename: nil).display_title
  end

  test "primary_first orders the Product image ahead of variants" do
    build(file_id: "V1", source_type: "ProductAttr", attribute1: "B").save!
    build(file_id: "P1", source_type: "Product").save!
    build(file_id: "V2", source_type: "ProductAttr", attribute1: "A").save!

    ordered = sku.sku_images.primary_first.map(&:file_id)
    assert_equal "P1", ordered.first                 # Product image leads
    assert_equal %w[V2 V1], ordered[1..]             # then variants by attribute1 (A before B)
  end
end
