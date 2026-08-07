module Rooms
  # Maps a NewStart room dictionary entry (room_code / room_desc) onto the
  # designer-facing RoomType vocabulary.
  #
  # ORDER IS LOAD-BEARING. The vocabulary keeps master/secondary/powder apart,
  # so the specific patterns must be tested before the generic ones: "Primary
  # Bath" has to reach :master_bathroom before the bare /bath/ rule claims it,
  # and a powder room has to be caught before either. A mis-ordered rule files
  # every master bath as secondary, silently.
  class Classifier
    RULES = [
      # Not a single room at all — catalog entries covering the whole house.
      # First, because several contain words other rules would claim.
      [ :whole_home, /\b(interior\s+of\s+home|whole\s*home|included\s+\w+\s+areas|drawn\s+options)\b/i ],

      # Powder before closet: a "water closet" is a toilet room, not storage.
      # Also before every bath rule, since a powder room is a half bath.
      [ :powder_bath, /\b(powder|half\s*bath|pwdr?|wc|water\s*closet)\b/i ],

      # A closet is a closet regardless of what it hangs off — "Foyer Closet",
      # "Flex Closet", "Primary Bed WIC" — so it precedes the room rules that
      # would otherwise claim it by its qualifier.
      [ :closet, /\b(closet|clst|wic|wardrobe)\b/i ],

      # Master/owner/primary, still ahead of the generic bed/bath rules.
      [ :master_bathroom, /\b(master|owner'?s?|primary|mstr)\b.*\bbath/i ],
      [ :master_bathroom, /\b(m|own|prim)bath\b/i ],
      [ :master_bedroom, /\b(master|owner'?s?|primary|mstr)\b.*\b(bed|bdrm|suite)/i ],
      [ :master_bedroom, /\b(m|own|prim)(bed|bdc|bdr)\w*\b/i ],

      # Rooms whose names contain "bath"/"bed" only incidentally.
      [ :laundry, /\b(laundry|utility|utl|util)\b/i ],
      [ :mudroom, /\b(mud\s*room|mudrm|drop\s*zone)\b/i ],

      [ :pantry, /\b(pantry|pntry)\b/i ],
      [ :kitchen, /\b(kitchen|kitchenette|ktch|kti|kit)\d*\b/i ],
      [ :dining_room, /\b(dining|breakfast|nook|dinette)\b/i ],
      [ :living_room, /\b(living|great\s*room|family\s*room|hearth|keeping|gathering)\b/i ],
      [ :den, /\bden\b/i ],
      [ :loft, /\bloft\b/i ],
      [ :game_room, /\b(game|bonus|media|rec\s*room|theater|entertainment)\b/i ],
      [ :office, /\b(office|study|library)\b/i ],
      [ :flex_room, /\bflex\b/i ],
      [ :entry, /\b(entry|foyer|vestibule|stoop|front\s+door)\b/i ],
      [ :hallway, /\b(hall|hallway|corridor|landing|stair\w*|gallery)\b/i ],

      # Generic bed/bath come BEFORE the location rules below, because names
      # like "Bed Over Garage" or "Bath Finished Basement" describe where the
      # room sits — the room noun is what the designer is photographing.
      # \w* rather than \d* so "Bedroom"/"Bathroom" match, not just "Bed 2".
      [ :secondary_bathroom, /\bbath\w*\b|\b(btr|btc)\d*\b/i ],
      [ :secondary_bedroom, /\bbed\w*\b|\b(bdrm|bdr|bdc|br)\d*\b/i ],

      [ :garage, /\b(garage|carport|gar\d*|xgar\d*)\b/i ],
      [ :basement, /\b(basement|bsmt|cellar)\b/i ],
      [ :outdoor_living, /\b(patio|deck|lanai|courtyard|porch|outdoor|balcony|terrace|screened)\b/i ],
      [ :exterior, /\b(exterior|extr|elevation|facade|roof|yard|landscape)\b/i ]
    ].freeze

    # Rooms we genuinely can't place land here rather than being guessed at.
    # Deliberately NOT flex_room: that is a real room designers choose, and
    # using it as the dustbin would quietly pollute a legitimate category.
    FALLBACK = :whole_home

    def self.key_for(room_code, room_desc = nil)
      haystack = [ room_desc, room_code ].compact_blank.join(" ")
      return FALLBACK if haystack.blank?

      RULES.find { |(_key, pattern)| haystack.match?(pattern) }&.first || FALLBACK
    end

    # key => room_type_id, for assigning in bulk during a sync.
    def self.ids_by_key
      RoomType.pluck(:key, :id).to_h
    end

    def self.room_type_id_for(room_code, room_desc = nil, ids: ids_by_key)
      ids[key_for(room_code, room_desc).to_s]
    end
  end
end
