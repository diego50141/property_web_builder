# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Resincronización periódica (Fase D del autopilot): re-importa las
    # propiedades de cada website provisionado desde Metrocuadrado, usando la
    # URL de agencia guardada en imports_config (SyncRegistry). El import es
    # idempotente (upsert por reference), así que altas, bajas de precio y
    # fotos nuevas se reflejan sin duplicar.
    #
    # MULTI-TENANCY: itera websites vía SyncRegistry.resyncable_websites
    # (cross-tenant); el Importer fija el tenant internamente con
    # ActsAsTenant.with_tenant.
    #
    # Schedule: diario (config/recurring.yml). Manual:
    #   Pwb::Metrocuadrado::ResyncJob.perform_later              # todos
    #   Pwb::Metrocuadrado::ResyncJob.perform_later(website_id: 123)
    class ResyncJob < Pwb::ApplicationJob
      queue_as :low

      # Errores de red transitorios: Http ya reintenta por request; si aun así
      # falla el job completo, Solid Queue lo reintenta con backoff.
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform(website_id: nil)
        websites = SyncRegistry.resyncable_websites
        websites = websites.where(id: website_id) if website_id

        websites.find_each do |website|
          resync(website)
        end
      end

      private

      def resync(website)
        agency_url = SyncRegistry.agency_url(website)
        results = Importer.new(website).import(agency_url)
        SyncRegistry.record(website, agency_url: agency_url, results: results)

        summary = SyncRegistry.summarize(results)
        Rails.logger.info(
          "[metrocuadrado] resync website ##{website.id} (#{website.subdomain}): " \
          "#{summary['imported']} importadas, #{summary['errors']} con error, #{summary['skipped']} omitidas"
        )
      rescue StandardError => e
        # Un sitio caído no debe frenar el resto; el resumen queda en el log.
        Rails.logger.error("[metrocuadrado] resync website ##{website.id} falló: #{e.class}: #{e.message}")
      end
    end
  end
end
