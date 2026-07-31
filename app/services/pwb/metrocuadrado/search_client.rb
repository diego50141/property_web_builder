# frozen_string_literal: true

require "json"
require "uri"

module Pwb
  module Metrocuadrado
    # Cliente del API REST interno del buscador de Metrocuadrado
    # (/rest-search/search), descubierto inspeccionando el tráfico de red del
    # propio sitio: NO es una API pública ni documentada, puede cambiar sin
    # aviso (nombres de parámetros, la api_key). A diferencia del resto del
    # pipeline (Extractor/Importer), acá no hace falta scraping HTML/regex:
    # el portal ya devuelve JSON limpio por resultado.
    #
    # Detalles verificados a mano contra el portal real:
    #   - size=50 es el mínimo que funciona; size=5 devuelve 0 resultados
    #     (comportamiento raro/bug del backend del portal, no un límite real).
    #   - roomList/bathroomList (no usados acá) filtran por coincidencia
    #     EXACTA, no por mínimo — el requerimiento "mínimo N habitaciones" se
    #     filtra en Ruby sobre los resultados (ver PropertyRequirementSearchService).
    #   - "venta" usa saleRange=min&saleRange=max (pesos, no centavos);
    #     "arriendo" usa leaseRange=min&leaseRange=max.
    #   - city= espera el slug verificado por Pwb::Metrocuadrado::CityMapper,
    #     no el nombre tal cual (ej. "santa-marta", no "santamarta").
    module SearchClient
      BASE_URL = "https://www.metrocuadrado.com/rest-search/search"
      MIN_SIZE = 50
      MAX_RESULTS_DEFAULT = 200

      # Key pública embebida en el bundle JS del propio sitio (no es un
      # secreto nuestro) — se puede sobreescribir vía credentials/ENV si el
      # portal la rota.
      DEFAULT_API_KEY = "P1MfFHfQMOtL16Zpg36NcntJYCLFm8FqFfudnavl"

      class MissingCityError < StandardError; end

      module_function

      # Una página de resultados crudos.
      # @return [Hash] { total_hits:, results: [Hash, ...] }
      def search(operation_type:, property_type_key:, city_slug:, price_min_cents: nil, price_max_cents: nil,
                 from: 0, size: MIN_SIZE)
        raise MissingCityError, "city_slug es requerido" if city_slug.blank?

        url = build_url(
          operation_type: operation_type, property_type_key: property_type_key, city_slug: city_slug,
          price_min_cents: price_min_cents, price_max_cents: price_max_cents, from: from, size: size
        )
        body = Http.fetch(url, headers: { "x-api-key" => api_key, "Accept" => "application/json" })
        data = JSON.parse(body)
        { total_hits: data["totalHits"].to_i, results: data["results"] || [] }
      end

      def city_slug_for(city_name)
        CityMapper.slug_for(city_name)
      end

      # Item crudo -> hash normalizado del service (misma forma que produce
      # Fincaraiz::SearchClient.normalize). rent: decide entre mvalorventa y
      # mvalorarriendo.
      def normalize(item, rent: false)
        {
          reference: item["midinmueble"].to_s,
          source_url: item["link"],
          title: item["title"],
          price_cents: (rent ? item["mvalorarriendo"] : item["mvalorventa"]).to_i * 100,
          bedrooms: item["mnrocuartos"].to_i,
          bathrooms: item["mnrobanos"].to_i,
          area: item["areaPrivada"] || item["marea"],
          city: item.dig("mciudad", "nombre"),
          neighborhood: item["mnombrecomunbarrio"] || item["mbarrio"],
          thumbnail_url: item["imageLink"],
          raw: item
        }
      end

      # Pagina automáticamente hasta cubrir totalHits o max_results (lo que sea menor).
      # roomList/bathroomList NO se usan a propósito: la API filtra por
      # coincidencia exacta, no por mínimo; esos criterios los aplica el
      # service en Ruby (bedrooms_min/bathrooms_min se aceptan y se ignoran
      # por uniformidad de interfaz con Fincaraiz::SearchClient).
      # @return [Array<Hash>] resultados crudos tal cual los devuelve el portal, sin deduplicar
      # rubocop:disable Lint/UnusedMethodArgument
      def search_all(max_results: MAX_RESULTS_DEFAULT, bedrooms_min: nil, bathrooms_min: nil, **filters)
        # rubocop:enable Lint/UnusedMethodArgument
        results = []
        from = 0

        loop do
          page = search(**filters, from: from, size: MIN_SIZE)
          results.concat(page[:results])
          from += MIN_SIZE
          break if page[:results].empty? || results.size >= max_results || results.size >= page[:total_hits]
        end

        results.first(max_results)
      end

      def build_url(operation_type:, property_type_key:, city_slug:, price_min_cents:, price_max_cents:, from:, size:)
        params = [
          ["size", size],
          ["from", from],
          ["realEstateTypeList", property_type_key],
          ["realEstateBusinessList", operation_type],
          ["city", city_slug]
        ]
        range_key = operation_type == "arriendo" ? "leaseRange" : "saleRange"
        # La API espera pesos, no centavos.
        params << [range_key, price_min_cents.to_i / 100] if price_min_cents.present?
        params << [range_key, price_max_cents.to_i / 100] if price_max_cents.present?

        "#{BASE_URL}?#{URI.encode_www_form(params)}"
      end

      def api_key
        creds = defined?(Rails) ? (Rails.application.credentials.metrocuadrado || {}) : {}
        creds[:api_key] || ENV["METROCUADRADO_API_KEY"] || DEFAULT_API_KEY
      end
    end
  end
end
