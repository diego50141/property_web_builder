# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Extracts the agency's own data (name, logo, phone, address, city) from
    # Metrocuadrado pages, to auto-provision a website for that agency.
    #
    # Sources (both are RSC/Next.js payloads with escaped quotes, same trick as
    # Extractor):
    #   - the agency page (/inmobiliaria/<slug>/<id>): h1 with the agency name,
    #     the listing URLs, and each card's city (mciudad) -> we take the most
    #     frequent city as the agency's city.
    #   - any property page of the agency: embeds a company block with
    #     companyName, companyImage (logo), companyAddress, companySeoUrl,
    #     contactPhone and whatsapp.
    class AgencyExtractor
      def initialize(agency_html, property_html = nil)
        @agency = agency_html.to_s.gsub('\\"', '"')
        @property = property_html.to_s.gsub('\\"', '"')
      end

      def call
        {
          name: name,
          slug: str(@property, "companySeoUrl"),
          company_id: str(@property, "companyId"),
          logo_url: logo_url,
          phone: str(@property, "contactPhone"),
          whatsapp: str(@property, "whatsapp"),
          street_address: str(@property, "companyAddress"),
          city: city,
          property_paths: property_paths
        }
      end

      def property_paths
        @agency.scan(%r{/inmueble/[a-z0-9\-]+/\d+-M\d+}i).uniq
      end

      private

      # "companyName":"LLANOCASA" from a property page; falls back to the
      # agency page h1 ("LLANOCASA - Inmobiliaria").
      def name
        from_property = str(@property, "companyName")
        return from_property if from_property

        m = @agency.match(/"h1":"([^"]+)"/)
        m && m[1].sub(/\s*-\s*Inmobiliaria\z/i, "").strip
      end

      def logo_url
        url = str(@property, "companyImage")
        url&.match?(%r{\Ahttps?://}i) ? url : nil
      end

      # Most frequent city across the agency's listing cards:
      # "mciudad":{"id":"16","nombre":"Villavicencio"}
      def city
        cities = @agency.scan(/"mciudad":\s*\{[^}]*?"nombre":"([^"]+)"/).flatten
        return nil if cities.empty?

        cities.tally.max_by { |_city, count| count }.first
      end

      def str(scope, key)
        m = scope.match(/"#{key}":"([^"]*)"/)
        v = m && m[1]
        v.nil? || v.empty? || v == "NA" || v == "null" ? nil : v
      end
    end
  end
end
