# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Traduce el nombre de ciudad que escribe el agente al slug que espera el
    # `city=` de /rest-search/search. No es "quitar tildes y listo": ciudades
    # de varias palabras usan guion (ej. "santa-marta", NO "santamarta" — este
    # último devuelve 0 resultados). Cada slug de esta tabla fue verificado a
    # mano contra el portal real; una ciudad no listada devuelve nil en vez de
    # arriesgar un slug inventado que silenciosamente traiga 0 resultados.
    #
    # Antes de agregar una ciudad nueva: probarla contra
    # https://www.metrocuadrado.com/rest-search/search?city=<slug>&... y
    # confirmar que "results" no viene vacío.
    module CityMapper
      SLUGS = {
        'bogota' => 'bogota',
        'bogotadc' => 'bogota',
        'medellin' => 'medellin',
        'cali' => 'cali',
        'cartagena' => 'cartagena',
        'cartagenadeindias' => 'cartagena',
        'barranquilla' => 'barranquilla',
        'bucaramanga' => 'bucaramanga',
        'pereira' => 'pereira',
        'santamarta' => 'santa-marta',
        'villavicencio' => 'villavicencio'
      }.freeze

      module_function

      # @param city_name [String] tal como lo escribe el agente (con o sin tildes/puntuación)
      # @return [String, nil] slug válido para la API, o nil si la ciudad no está verificada
      def slug_for(city_name)
        SLUGS[normalize(city_name)]
      end

      def known?(city_name)
        slug_for(city_name).present?
      end

      def normalize(city_name)
        city_name.to_s
                 .unicode_normalize(:nfkd)
                 .encode('ASCII', invalid: :replace, undef: :replace, replace: '')
                 .downcase
                 .gsub(/[^a-z]/, '')
      end
    end
  end
end
