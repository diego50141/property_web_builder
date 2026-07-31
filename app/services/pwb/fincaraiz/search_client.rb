# frozen_string_literal: true

require "json"

module Pwb
  module Fincaraiz
    # Búsqueda en Fincaraíz (fincaraiz.com.co, grupo InfoCasas) para los
    # requerimientos de clientes. A diferencia de Metrocuadrado no hay API
    # REST utilizable: el sitio es Next.js clásico y renderiza los resultados
    # en el servidor dentro de <script id="__NEXT_DATA__"> — así que se piden
    # las URLs SEO (sin api key) y se extrae ese JSON.
    #
    # Gramática de URL verificada a mano en el portal real (30-jul-2026):
    #   /{venta|arriendo}/{apartamentos|casas|...}/{ciudad}/{departamento}
    #     [/N-o-mas-habitaciones][/N-o-mas-banos]
    #     [/desde-PESOS][/hasta-PESOS][/paginaN]
    #
    #   - habitaciones/baños son filtros de MÍNIMO nativos ("2 o más"), al
    #     revés que Metrocuadrado (que solo filtra por igualdad exacta).
    #     La UI del portal ofrece hasta 4+/3+; se clampa y el resto lo cubre
    #     el filtro local del service.
    #   - precios en pesos (venta: total, arriendo: mensual).
    #   - paginación SOLO por segmento /paginaN (?pagina= se ignora); 21 por página.
    #   - datos en props.pageProps.fetchResult.searchFast.{data,paginatorInfo}.
    module SearchClient
      BASE_URL = "https://www.fincaraiz.com.co"
      PER_PAGE = 21
      MAX_RESULTS_DEFAULT = 200
      MAX_ROOMS_FILTER = 4
      MAX_BATHS_FILTER = 3

      # Ciudad -> par ciudad/departamento de la URL. Cada par está verificado
      # contra el portal real; una ciudad fuera de esta tabla devuelve nil
      # (mismo criterio que Metrocuadrado::CityMapper: nunca inventar slugs).
      CITY_SLUGS = {
        "bogota" => "bogota/bogota-dc",
        "bogotadc" => "bogota/bogota-dc",
        "medellin" => "medellin/antioquia",
        "cali" => "cali/valle-del-cauca",
        "cartagena" => "cartagena/bolivar",
        "cartagenadeindias" => "cartagena/bolivar",
        "barranquilla" => "barranquilla/atlantico",
        "bucaramanga" => "bucaramanga/santander",
        "pereira" => "pereira/risaralda",
        "santamarta" => "santa-marta/magdalena",
        "villavicencio" => "villavicencio/meta"
      }.freeze

      # property_type_key (vocabulario Metrocuadrado, el del requirement) ->
      # segmento plural de Fincaraíz. Todos verificados con HTTP 200 + resultados.
      TYPE_SLUGS = {
        "apartamento" => "apartamentos",
        "apartaestudio" => "apartaestudios",
        "casa" => "casas",
        "oficina" => "oficinas",
        "local" => "locales",
        "lote" => "lotes",
        "finca" => "fincas",
        "bodega" => "bodegas"
      }.freeze

      # Claves pesadas del item que no vale la pena persistir en raw_data.
      RAW_DATA_SKIP = %w[description facilities images files occupancies seasons
                         technicalSheet socialMediaLinks finances].freeze

      module_function

      def city_slug_for(city_name)
        CITY_SLUGS[Metrocuadrado::CityMapper.normalize(city_name)]
      end

      # Pagina hasta max_results o hasta la última página.
      # @return [Array<Hash>] items crudos del portal
      def search_all(operation_type:, property_type_key:, city_slug:,
                     price_min_cents: nil, price_max_cents: nil,
                     bedrooms_min: nil, bathrooms_min: nil,
                     max_results: MAX_RESULTS_DEFAULT)
        results = []
        page = 1

        loop do
          url = build_url(
            operation_type: operation_type, property_type_key: property_type_key,
            city_slug: city_slug, price_min_cents: price_min_cents,
            price_max_cents: price_max_cents, bedrooms_min: bedrooms_min,
            bathrooms_min: bathrooms_min, page: page
          )
          data, paginator = parse_page(Metrocuadrado::Http.fetch(url))
          results.concat(data)
          break if data.empty? || results.size >= max_results
          break if paginator["lastPage"].to_i <= page

          page += 1
        end

        results.first(max_results)
      end

      def build_url(operation_type:, property_type_key:, city_slug:, price_min_cents: nil,
                    price_max_cents: nil, bedrooms_min: nil, bathrooms_min: nil, page: 1)
        type_slug = TYPE_SLUGS.fetch(property_type_key, "apartamentos")
        segments = [operation_type == "arriendo" ? "arriendo" : "venta", type_slug, city_slug]
        if bedrooms_min.to_i.positive?
          segments << "#{[bedrooms_min.to_i, MAX_ROOMS_FILTER].min}-o-mas-habitaciones"
        end
        if bathrooms_min.to_i.positive?
          segments << "#{[bathrooms_min.to_i, MAX_BATHS_FILTER].min}-o-mas-banos"
        end
        segments << "desde-#{price_min_cents.to_i / 100}" if price_min_cents.present?
        segments << "hasta-#{price_max_cents.to_i / 100}" if price_max_cents.present?
        segments << "pagina#{page}" if page > 1

        "#{BASE_URL}/#{segments.join('/')}"
      end

      # @return [Array(Array<Hash>, Hash)] [items, paginatorInfo]
      def parse_page(html)
        m = html.match(%r{<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>}m)
        raise "Fincaraíz: no se encontró __NEXT_DATA__ (¿cambió el portal?)" unless m

        search = JSON.parse(m[1]).dig("props", "pageProps", "fetchResult", "searchFast")
        raise "Fincaraíz: la página no trae searchFast (¿cambió el portal?)" unless search

        [search["data"] || [], search["paginatorInfo"] || {}]
      end

      # Item crudo -> hash normalizado del service (mismas claves que produce
      # Metrocuadrado::SearchClient.normalize). Acepta rent: por uniformidad
      # de interfaz, pero acá price.amount ya es el precio de la operación.
      def normalize(item, **)
        {
          reference: item["id"].to_s,
          source_url: "#{BASE_URL}#{item['link']}",
          title: item["title"],
          price_cents: item.dig("price", "amount").to_i * 100,
          bedrooms: item["bedrooms"].to_i,
          bathrooms: item["bathrooms"].to_i,
          area: item["m2"] || item["m2Built"],
          city: item.dig("locations", "city", 0, "name"),
          neighborhood: item.dig("locations", "location_main", "name"),
          thumbnail_url: item.dig("images", 0, "image") || item["img"],
          raw: item.except(*RAW_DATA_SKIP)
        }
      end
    end
  end
end
