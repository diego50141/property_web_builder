# frozen_string_literal: true

require "net/http"
require "uri"

module Pwb
  module Metrocuadrado
    # Plain-HTTP fetching shared by the importer and the auto-provisioner.
    # Metrocuadrado serves the full RSC payload to a simple GET with a browser
    # User-Agent (no Playwright needed).
    module Http
      USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                   "(KHTML, like Gecko) Chrome/120 Safari/537.36"

      module_function

      def fetch(url, limit = 5)
        raise "demasiados redirects" if limit.zero?

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 15
        http.read_timeout = 30
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = USER_AGENT
        res = http.request(req)
        case res
        when Net::HTTPSuccess
          # Net::HTTP returns the body as ASCII-8BIT (binary); force UTF-8 so
          # accented strings (Bogotá, Restrepo) transliterate when Rails builds
          # slugs. Metrocuadrado serves UTF-8.
          res.body.to_s.dup.force_encoding(Encoding::UTF_8)
        when Net::HTTPRedirection then fetch(res["location"], limit - 1)
        else raise "HTTP #{res.code} al pedir #{url}"
        end
      end
    end
  end
end
