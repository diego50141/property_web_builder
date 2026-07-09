# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Registro por-website del origen de importación (Fase D). Guarda en
    # website.imports_config["metrocuadrado"] la URL de la agencia y el
    # resumen del último sync; la resincronización periódica (ResyncJob)
    # descubre los sitios a refrescar a través de este registro.
    #
    # Estructura:
    #   imports_config["metrocuadrado"] = {
    #     "agency_url"     => "https://www.metrocuadrado.com/inmobiliaria/...",
    #     "auto_resync"    => true,   # false lo excluye del ResyncJob
    #     "last_synced_at" => "2026-07-09T12:00:00Z",
    #     "last_result"    => { "imported" => 20, "errors" => 0, "skipped" => 0 }
    #   }
    module SyncRegistry
      KEY = "metrocuadrado"

      module_function

      def record(website, agency_url:, results:)
        config = (website.imports_config || {}).deep_dup
        entry = (config[KEY] || {}).merge(
          "agency_url" => agency_url,
          "last_synced_at" => Time.current.iso8601,
          "last_result" => summarize(results)
        )
        entry["auto_resync"] = true unless entry.key?("auto_resync")
        config[KEY] = entry
        website.update!(imports_config: config)
      end

      def summarize(results)
        {
          "imported" => results.count { |r| r.action == "imported" },
          "errors" => results.count { |r| r.action == "error" },
          "skipped" => results.count { |r| r.action == "skipped" }
        }
      end

      def agency_url(website)
        website.imports_config&.dig(KEY, "agency_url")
      end

      # Websites con resync habilitado (y aún operativos).
      def resyncable_websites
        Pwb::Website.unscoped
                    .where.not(provisioning_state: %w[suspended terminated failed])
                    .where("(imports_config -> :key ->> 'auto_resync') = 'true'", key: KEY)
                    .where.not("(imports_config -> :key ->> 'agency_url') IS NULL", key: KEY)
      end
    end
  end
end
