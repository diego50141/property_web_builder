# frozen_string_literal: true

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

      def fetch(url)
        Http.fetch(url)
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

        listing.title_es = display_title(data) || "#{data[:property_type_name]} en #{data[:city]}"
        listing.description_es = data[:description] if data[:description]
        listing.save!
        listing
      end

      # El título OpenGraph del portal viene como
      # "Venta de Casa en Condominio X - Restrepo - 16573-M5446068":
      # quitamos el prefijo de negocio (la sección Comprar/Arrendar ya lo
      # dice, y en las tarjetas se leía "venta de casa, venta de finca...")
      # y la referencia del final.
      def display_title(data)
        title = data[:title].to_s.strip
        return nil if title.empty?

        title = title.sub(/\s*-?\s*#{Regexp.escape(data[:reference].to_s)}\z/i, "") if data[:reference]
        title = title.sub(/\A(venta o arriendo|venta|arriendo)\s+de\s+/i, "")
        title = title.sub(/\s+en\s+(venta o arriendo|venta|arriendo)\b/i, "")
        title = title.strip.presence
        title && title[0].upcase + title[1..]
      end

      # Returns number of photos attached.
      #
      # Fase D: si las URLs del portal no cambiaron, no toca las fotos — así
      # los attachments ya descargados (DownloadScrapedImagesJob) sobreviven
      # al resync periódico. Cuando sí cambian, reemplaza y encola la descarga
      # a ActiveStorage/R2 conservando external_url como procedencia (el
      # attachment tiene prioridad al servir; ver ExternalImageSupport).
      def replace_photos(asset, images)
        return 0 if images.nil? || images.empty?

        current = asset.prop_photos.order(:sort_order, :id).pluck(:external_url)
        return current.length if current == images

        asset.prop_photos.destroy_all
        count = 0
        images.each_with_index do |img_url, i|
          asset.prop_photos.create!(external_url: img_url, sort_order: i)
          count += 1
        rescue StandardError => e
          Rails.logger.warn("[metrocuadrado] foto omitida (#{img_url}): #{e.message}")
        end
        enqueue_photo_download(asset) if count.positive?
        count
      end

      def enqueue_photo_download(asset)
        Pwb::DownloadScrapedImagesJob.perform_later(asset.id, replace_external: false)
      rescue StandardError => e
        Rails.logger.warn("[metrocuadrado] no se pudo encolar la descarga de fotos: #{e.message}")
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
