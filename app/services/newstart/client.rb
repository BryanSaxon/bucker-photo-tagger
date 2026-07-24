require "net/http"
require "json"
require "erb"

module Newstart
  # Thin read-only client for the NewStart SKU/product catalog API.
  #
  # The API is documented in newstart-api-field-guide.html. Key facts baked in
  # here: auth is a Rails-style structured token header carrying BOTH a token and
  # an email, every endpoint is GET, and there is no pagination — /product_library
  # returns the entire catalog in a single response wrapped as { "products": [...] }.
  #
  # Configure via environment variables (or Rails credentials under :newstart):
  #   NEWSTART_API_BASE_URL   e.g. https://api.example.com
  #   NEWSTART_API_TOKEN      the API token
  #   NEWSTART_API_EMAIL      the account email tied to the token
  class Client
    class NotConfiguredError < StandardError; end
    class RequestError < StandardError; end

    API_VERSION = "v4".freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    def initialize(base_url: nil, token: nil, email: nil)
      creds = Rails.application.credentials.newstart || {}
      @base_url = (base_url || ENV["NEWSTART_API_BASE_URL"] || creds[:base_url]).to_s.chomp("/")
      @token    = token || ENV["NEWSTART_API_TOKEN"] || creds[:token]
      @email    = email || ENV["NEWSTART_API_EMAIL"] || creds[:email]
    end

    def configured?
      @base_url.present? && @token.present? && @email.present?
    end

    # Returns the full product catalog as an array of hashes (string keys).
    def product_library
      get("/product_library").fetch("products", [])
    end

    # Returns the full product-image index. Each entry carries a product_code,
    # filename, filemimetype, file_id, source_type and variant attributes — but
    # note this deployment exposes no endpoint to download the image bytes.
    def product_images
      get("/product_images").fetch("images", [])
    end

    # --- Community-rooted object graph --------------------------------------
    # Every community-scoped endpoint takes the community's project_code in the
    # path. Responses wrap their array under a plural key; we unwrap here.

    # All communities (the root of the graph). Each carries project_code, name
    # and product_library_code.
    def communities
      get("/communities").fetch("communities", [])
    end

    # Models for a community. Uses the models2 variant, which is a superset of
    # /models: more rows (incl. discontinued) plus square_feet, bed/bath/garage
    # counts and sellable/discontinued flags. Each model embeds the community's
    # room dictionary inline under "rooms".
    def community_models(project_code)
      get("/communities/#{seg(project_code)}/models2").fetch("models", [])
    end

    # Lots for a community (summary rows: address, status, type, prices).
    def community_lots(project_code)
      get("/communities/#{seg(project_code)}/lots").fetch("lots", [])
    end

    # A single lot with its configured selections. Returns the lot hash, which
    # embeds available_rooms, selected_drawn_options and selected_design_options,
    # or nil if the lot is not found.
    def community_lot(project_code, lot_number)
      get("/communities/#{seg(project_code)}/lots/#{seg(lot_number)}").fetch("lot", []).first
    end

    # Priced options for a community (the "Drawn Options" set), joined to a model
    # by model + elev and to a product by product_code.
    def community_options(project_code)
      get("/communities/#{seg(project_code)}/options").fetch("options", [])
    end

    # The configurator step / category / subcategory display tree for a community
    # (display names + sort order only — no category codes are exposed here).
    def community_steps(project_code)
      get("/communities/#{seg(project_code)}/steps").fetch("steps", [])
    end

    private

    # URL-encode a single path segment (project_code and lot are strings that can
    # in principle contain unsafe characters).
    def seg(value)
      ERB::Util.url_encode(value.to_s)
    end

    def get(path)
      ensure_configured!

      uri = URI.parse("#{@base_url}/api/#{API_VERSION}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = %(Token token="#{@token}", email="#{@email}")
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "GET #{path} returned #{response.code} #{response.message}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise RequestError, "GET #{path} returned invalid JSON: #{e.message}"
    rescue SocketError, Timeout::Error, SystemCallError => e
      raise RequestError, "GET #{path} failed: #{e.message}"
    end

    def ensure_configured!
      return if configured?

      raise NotConfiguredError,
        "NewStart API is not configured. Set NEWSTART_API_BASE_URL, " \
        "NEWSTART_API_TOKEN and NEWSTART_API_EMAIL (or credentials.newstart)."
    end
  end
end
