module Photos
  # What the image toolchain on this machine can actually decode.
  #
  # HEIC needs libvips built with libheif AND an HEVC decoder (libde265).
  # Installing libheif without a decoder yields a libvips that advertises HEIF
  # support and then fails on every real iPhone file, so this probes by asking
  # vips for its suffix list rather than trusting the gem being present.
  module ImageSupport
    HEIC_SUFFIXES = /\.hei[cf]/i

    # Content types Photos::PrepareImageJob rewrites to JPEG on upload. A blob
    # still carrying one of these is a source that is about to be replaced.
    CONVERTIBLE_TYPES = %w[ image/heic image/heif ].freeze

    def self.heic_available?
      return @heic_available unless @heic_available.nil?

      @heic_available = probe_heic
    end

    # Test seam: lets a spec assert both the supported and unsupported paths.
    def self.reset!
      @heic_available = nil
    end

    def self.probe_heic
      require "vips"
      available = Vips.get_suffixes.any? { |suffix| suffix.match?(HEIC_SUFFIXES) }
      Rails.logger.info({ event: "image_support.probe", heic: available }.to_json)
      available
    rescue LoadError, StandardError => e
      Rails.logger.warn({ event: "image_support.probe_failed", error: e.class.name }.to_json)
      false
    end
    private_class_method :probe_heic
  end
end
