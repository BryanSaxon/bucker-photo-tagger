require "net/http"
require "json"

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

    private

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
