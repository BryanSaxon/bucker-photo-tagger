module Catalog
  # Small value coercions shared across the catalog syncers. The API returns
  # numbers as strings (often blank), so these normalize to nil rather than 0.
  module Casts
    module_function

    def decimal(value)
      s = value.to_s.strip
      return nil if s.empty?
      BigDecimal(s)
    rescue ArgumentError
      nil
    end

    def integer(value)
      s = value.to_s.strip
      return nil if s.empty?
      Integer(s, exception: false) || s.to_f.to_i
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    # Comma-joined code lists (room codes, area associations) → array of tokens.
    def csv(value)
      value.to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
