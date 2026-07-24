require "test_helper"

module Newstart
  class ClientTest < ActiveSupport::TestCase
    # Minimal stand-in for a Net::HTTPResponse: the decoder only needs
    # #content_type and #body.
    FakeResponse = Struct.new(:content_type, :body)

    def decode(response, name = "AAA.JPG")
      Client.new.send(:decode_image_response, response, name)
    end

    test "decodes a raw binary response into image bytes" do
      resp = FakeResponse.new("image/jpeg", "\x89PNG\r\n\x1a\n-binary")

      file = decode(resp)

      assert_equal "\x89PNG\r\n\x1a\n-binary", file.body
      assert_equal "image/jpeg", file.content_type
      assert_equal "AAA.JPG", file.filename
    end

    test "falls back to octet-stream when the binary response has no content type" do
      file = decode(FakeResponse.new(nil, "bytes"))

      assert_equal "application/octet-stream", file.content_type
    end

    test "decodes base64 bytes wrapped in a JSON response" do
      raw = "the-real-image-bytes"
      body = { "file_contents" => Base64.strict_encode64(raw),
               "filemimetype" => "image/png", "filename" => "server-name.png" }.to_json
      resp = FakeResponse.new("application/json; charset=utf-8", body)

      file = decode(resp)

      assert_equal raw, file.body
      assert_equal "image/png", file.content_type
      assert_equal "server-name.png", file.filename   # server filename wins over the passed name
    end

    test "raises when a JSON response carries no recognizable payload" do
      resp = FakeResponse.new("application/json", { "error" => "not found" }.to_json)

      assert_raises(Client::RequestError) { decode(resp) }
    end

    test "product_image_file_contents rejects a blank image name before any request" do
      assert_raises(Client::RequestError) do
        Client.new.product_image_file_contents("")
      end
    end
  end
end
