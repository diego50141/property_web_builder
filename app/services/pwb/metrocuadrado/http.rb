# frozen_string_literal: true

require "net/http"
require "uri"

module Pwb
  module Metrocuadrado
    # Plain-HTTP fetching shared by the importer and the auto-provisioner.
    # Metrocuadrado serves the full RSC payload to a simple GET with a browser
    # User-Agent (no Playwright needed).
    #
    # Fase D: incluye rate-limit (pausa mínima entre requests, para no golpear
    # el portal) y reintentos con backoff ante errores transitorios (timeouts,
    # HTTP 429/5xx). Ambos se anulan en specs con `Http.throttle_seconds = 0`,
    # que también deja el backoff en cero.
    module Http
      USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                   "(KHTML, like Gecko) Chrome/120 Safari/537.36"
      MAX_ATTEMPTS = 3

      # HTTP 429/5xx del portal; se reintenta con backoff.
      class RetryableError < StandardError; end

      RETRIABLE_EXCEPTIONS = [
        RetryableError, Net::OpenTimeout, Net::ReadTimeout,
        Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
      ].freeze

      module_function

      # Pausa mínima entre requests, en segundos. Configurable con
      # METROCUADRADO_THROTTLE_SECONDS; en test es 0 (sin sleeps ni backoff).
      def throttle_seconds
        @throttle_seconds ||= ENV.fetch("METROCUADRADO_THROTTLE_SECONDS") do
          defined?(Rails) && Rails.env.test? ? "0" : "0.5"
        end.to_f
      end

      def throttle_seconds=(value)
        @throttle_seconds = value
      end

      # headers: extra request headers (ej. x-api-key para el rest-search API).
      def fetch(url, limit = 5, headers: {})
        raise "demasiados redirects" if limit.zero?

        res = request_with_retries(url, headers)
        case res
        when Net::HTTPSuccess
          # Net::HTTP returns the body as ASCII-8BIT (binary); force UTF-8 so
          # accented strings (Bogotá, Restrepo) transliterate when Rails builds
          # slugs. Metrocuadrado serves UTF-8.
          res.body.to_s.dup.force_encoding(Encoding::UTF_8)
        # Location puede venir relativo (Fincaraíz lo hace); se resuelve
        # contra la URL actual.
        when Net::HTTPRedirection then fetch(URI.join(url, res["location"]).to_s, limit - 1, headers: headers)
        else raise "HTTP #{res.code} al pedir #{url}"
        end
      end

      def request_with_retries(url, headers = {})
        attempts = 0
        begin
          attempts += 1
          throttle!
          res = request(url, headers)
          if res.is_a?(Net::HTTPTooManyRequests) || res.is_a?(Net::HTTPServerError)
            raise RetryableError, "HTTP #{res.code} al pedir #{url}"
          end

          res
        rescue *RETRIABLE_EXCEPTIONS => e
          raise "#{e.message} (tras #{attempts} intentos)" if attempts >= MAX_ATTEMPTS

          sleep(throttle_seconds * (2**attempts))
          retry
        end
      end

      def request(url, headers = {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 15
        http.read_timeout = 30
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = USER_AGENT
        headers.each { |k, v| req[k.to_s] = v }
        http.request(req)
      end

      # Espacia requests consecutivos al portal.
      def throttle!
        return if throttle_seconds <= 0

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @last_request_at && (wait = throttle_seconds - (now - @last_request_at)).positive?
          sleep(wait)
        end
        @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
