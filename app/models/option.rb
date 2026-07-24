class Option < ApplicationRecord
  # A priced "Drawn Option" available in a community, joined to a product by
  # product_code and to a model by free-text model + elev (best-effort, so
  # floorplan may be nil).
  belongs_to :community
  belongs_to :sku, optional: true
  belongs_to :floorplan, optional: true

  # room_replacement_rules on the source encode how choosing this option mutates
  # the room set; stored as comma-joined room_code strings.
  def add_room_codes
    room_replacement_add.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def remove_room_codes
    room_replacement_remove.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
