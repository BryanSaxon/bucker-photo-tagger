require "net/http"
require "json"
require "base64"
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

    # The decoded bytes of a single product image plus the content type and a
    # filename to attach it under.
    ImageFile = Struct.new(:body, :content_type, :filename, keyword_init: true)

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
    # filename, filemimetype, file_id, source_type and variant attributes.
    def product_images
      get("/product_images").fetch("images", [])
    end

    # Downloads the bytes for a single product image and returns an ImageFile.
    #
    # The field guide documents GET /product_images/{image_name}/file_contents
    # but marks it UNVERIFIED, and how {image_name} is derived from a product is
    # an open question — we pass the image's `filename`, which is what the path
    # parameter is named after. The response may be raw binary OR base64 wrapped
    # in JSON, so both are handled here based on the Content-Type. `image_name`
    # is URL-encoded because filenames routinely contain spaces and other unsafe
    # characters.
    def product_image_file_contents(image_name)
      raise RequestError, "image_name is blank" if image_name.to_s.strip.empty?

      encoded = ERB::Util.url_encode(image_name.to_s)
      response = request_raw("/product_images/#{encoded}/file_contents")
      decode_image_response(response, image_name)
    end

    private

    def get(path)
      response = request_raw(path, accept: "application/json")
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise RequestError, "GET #{path} returned invalid JSON: #{e.message}"
    end

    # Performs the GET and returns the raw Net::HTTPResponse (no body parsing),
    # raising RequestError on any non-success status or transport failure. Shared
    # by the JSON endpoints and the binary image download.
    def request_raw(path, accept: "*/*")
      ensure_configured!

      uri = URI.parse("#{@base_url}/api/#{API_VERSION}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = %(Token token="#{@token}", email="#{@email}")
      request["Accept"] = accept

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "GET #{path} returned #{response.code} #{response.message}"
      end

      response
    rescue SocketError, Timeout::Error, SystemCallError => e
      raise RequestError, "GET #{path} failed: #{e.message}"
    end

    # Turns the file_contents response into an ImageFile. A JSON content type
    # means the bytes are base64-encoded inside an object (we look for the usual
    # key names); anything else is treated as the raw image bytes.
    def decode_image_response(response, image_name)
      content_type = response.content_type.to_s

      if content_type.include?("json")
        data = JSON.parse(response.body)
        b64 = data["file_contents"] || data["contents"] || data["data"] || data["base64"]
        raise RequestError, "image JSON had no recognizable base64 payload" if b64.blank?

        ImageFile.new(
          body: Base64.decode64(b64),
          content_type: data["filemimetype"] || data["content_type"] || "application/octet-stream",
          filename: data["filename"] || image_name
        )
      else
        ImageFile.new(
          body: response.body,
          content_type: content_type.presence || "application/octet-stream",
          filename: image_name
        )
      end
    rescue JSON::ParserError => e
      raise RequestError, "image download returned invalid JSON: #{e.message}"
    end

    def ensure_configured!
      return if configured?

      raise NotConfiguredError,
        "NewStart API is not configured. Set NEWSTART_API_BASE_URL, " \
        "NEWSTART_API_TOKEN and NEWSTART_API_EMAIL (or credentials.newstart)."
    end
  end
end
