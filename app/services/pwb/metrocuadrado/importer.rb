# frozen_string_literal: true

require "net/http"
require "uri"

module Pwb
  module Metrocuadrado
    # Imports properties into a website (tenant) from a Metrocuadrado URL.
    #
    # Accepts either:
    #   - an agency page (/inmobiliaria/<slug>/<id>) -> imports every listing, or
    #   - a single property page (/inmueble/<slug>/<id>-M<code>).
    #
    # Idempotent: re-running upserts by `reference` (the Metrocuadrado id), so
    # properties are updated in place rather than duplicated. Photos are stored
    # as external URLs (no download) via PropPhoto#external_url.
    class Importer
      BASE = "https://www.metrocuadrado.com"
      USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                   "(KHTML, like Gecko) Chrome/120 Safari/537.36"

      Result = Struct.new(:reference, :title, :action, :photos, :error, keyword_init: true)

      def initialize(website)
        @website = website
      end

      # @return [Array<Result>]
      def import(url)
        results = if url.include?("/inmobiliaria/")
                    import_agency(url)
                  else
                    [import_property(url)]
                  end
        refresh_public_view
        results
      end

      def import_agency(agency_url)
        html = fetch(agency_url)
        paths = html.gsub('\\"', '"')
                    .scan(%r{/inmueble/[a-z0-9\-]+/\d+-M\d+}i)
                    .uniq
        paths.map { |path| import_property(BASE + path) }
      end

      def import_property(url)
        data = nil
        html = fetch(url)
        data = Extractor.new(html, url).call
        if data[:reference].nil?
          return Result.new(reference: nil, action: "skipped", error: "sin reference")
        end

        photos = 0
        ActsAsTenant.with_tenant(@website) do
          asset = upsert_asset(data)
          upsert_listing(asset, data)
          photos = replace_photos(asset, data[:images])
        end
        Result.new(reference: data[:reference], title: data[:title], action: "imported", photos: photos)
      rescue StandardError => e
        Result.new(reference: data && data[:reference], action: "error", error: e.message)
      end

      private

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

      def upsert_asset(data)
        asset = Pwb::RealtyAsset.find_or_initialize_by(website: @website, reference: data[:reference])
        asset.assign_attributes(
          count_bedrooms: data[:bedrooms] || 0,
          count_bathrooms: data[:bathrooms] || 0,
          count_garages: data[:garages] || 0,
          constructed_area: data[:constructed_area],
          plot_area: data[:plot_area],
          city: data[:city],
          country: "CO",
          street_address: data[:common_neighborhood] || data[:neighborhood],
          prop_type_key: data[:prop_type_key]
        )
        asset.save!
        asset
      end

      def upsert_listing(asset, data)
        rent = data[:business_type].to_s.downcase.start_with?("arr") ||
               (data[:rent_price].to_i.positive? && data[:sale_price].to_i.zero?)

        if rent
          listing = asset.rental_listings.first_or_initialize
          listing.active = true
          listing.visible = true
          if listing.respond_to?(:price_rental_monthly_current_cents=)
            listing.price_rental_monthly_current_cents = data[:rent_price].to_i * 100
            listing.price_rental_monthly_current_currency = "COP"
          end
        else
          listing = asset.sale_listings.first_or_initialize
          listing.active = true
          listing.visible = true
          listing.price_sale_current_cents = data[:sale_price].to_i * 100
          listing.price_sale_current_currency = "COP"
        end
        listing.save!

        listing.title_es = data[:title] || "#{data[:property_type_name]} en #{data[:city]}"
        listing.description_es = data[:description] if data[:description]
        listing.save!
        listing
      end

      # Returns number of photos attached.
      def replace_photos(asset, images)
        return 0 if images.nil? || images.empty?

        asset.prop_photos.destroy_all
        count = 0
        images.each_with_index do |img_url, i|
          asset.prop_photos.create!(external_url: img_url, sort_order: i)
          count += 1
        rescue StandardError => e
          Rails.logger.warn("[metrocuadrado] foto omitida (#{img_url}): #{e.message}")
        end
        count
      end

      def refresh_public_view
        return unless defined?(Pwb::ListedProperty) && Pwb::ListedProperty.respond_to?(:refresh)

        Pwb::ListedProperty.refresh
      rescue StandardError => e
        Rails.logger.warn("[metrocuadrado] ListedProperty.refresh: #{e.message}")
      end
    end
  end
end
