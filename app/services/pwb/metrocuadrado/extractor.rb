# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Extracts structured property data from a Metrocuadrado property page.
    #
    # Metrocuadrado is a Next.js app that embeds the property's data object
    # inside the RSC streaming payload with escaped quotes (\"). We unescape a
    # working copy and pull fields with regexes anchored to the property's own
    # id (so nearby "similar listings" don't contaminate the result), plus
    # OpenGraph tags for title/description and the predictable image URL pattern
    # (multimedia.metrocuadrado.com/<id>/<id>_<n>_x.jpg).
    class Extractor
      # Metrocuadrado property-type name -> PWB prop_type_key (field_keys tag
      # "property-types", values like "types.apartment").
      TYPE_MAP = {
        "apartamento" => "types.apartment",
        "apartaestudio" => "types.studio",
        "casa" => "types.detached_house",
        "casa campestre" => "types.country_house",
        "finca" => "types.country_house",
        "lote" => "types.land",
        "oficina" => "types.office",
        "local" => "types.commercial",
        "local comercial" => "types.commercial",
        "consultorio" => "types.office",
        "bodega" => "types.warehouse",
        "edificio" => "types.residential_building",
        "cabaña" => "types.country_house"
      }.freeze

      def initialize(html, url)
        @raw = html.to_s
        @txt = @raw.gsub('\\"', '"')
        @url = url.to_s
      end

      def call
        pid = property_id
        w = anchored_window(pid)
        type_name = subobj_name(w, "propertyType")
        {
          reference: pid,
          source_url: @url,
          business_type: str(w, "businessType") || "venta",
          sale_price: int(w, "salePrice"),
          rent_price: int(w, "rentPrice"),
          plot_area: int(w, "area"),
          constructed_area: int(w, "areac"),
          bedrooms: int_str(w, "rooms"),
          bathrooms: int_str(w, "bathrooms"),
          garages: int_str(w, "garages"),
          stratum: int_str(w, "stratum"),
          property_type_name: type_name,
          prop_type_key: type_key(type_name),
          city: subobj_name(w, "city"),
          neighborhood: str(w, "neighborhood"),
          common_neighborhood: str(w, "commonNeighborhood"),
          title: og("title"),
          description: description(w),
          images: images(pid)
        }
      end

      private

      def property_id
        m = @url.match(%r{/(\d+-M\d+)})
        return m[1] if m

        m2 = @txt.match(/"propertyId":"([\w\-]+)"/)
        m2 && m2[1]
      end

      # Restrict extraction to the property's own data object.
      def anchored_window(pid)
        return @txt unless pid

        idx = @txt.index(%("propertyId":"#{pid}"))
        idx ? (@txt[idx, 4000] || @txt) : @txt
      end

      def int(scope, key)
        m = scope.match(/"#{key}":(\d+)/)
        m && m[1].to_i
      end

      def int_str(scope, key)
        m = scope.match(/"#{key}":"?(\d+)"?/)
        m && m[1].to_i
      end

      def str(scope, key)
        m = scope.match(/"#{key}":"([^"]*)"/)
        v = m && m[1]
        v.nil? || v.empty? || v == "NA" ? nil : v
      end

      def subobj_name(scope, key)
        m = scope.match(/"#{key}":\s*\{[^}]*?"nombre":"([^"]+)"/)
        m && m[1]
      end

      def type_key(name)
        return nil if name.nil?

        TYPE_MAP[name.to_s.strip.downcase] || "types.apartment"
      end

      def og(prop)
        m = @raw.match(/<meta property="og:#{prop}" content="([^"]*)"/)
        m && m[1]
      end

      def description(scope)
        text = og("description")
        if text.nil? || text.strip.empty?
          m = scope.match(/"comment":"(.*?)","[a-zA-Z]+":/m)
          text = m && m[1]
        end
        return nil if text.nil?

        text.gsub('\\n', "\n").gsub('\\/', "/").strip
      end

      def images(pid)
        return [] if pid.nil?

        @raw.scan(%r{https://multimedia\.metrocuadrado\.com/#{Regexp.escape(pid)}/[\w\-]+\.(?:jpg|jpeg|webp|png)}i)
            .uniq
            .sort_by { |u| (u[/_(\d+)_/, 1] || "0").to_i }
      end
    end
  end
end
