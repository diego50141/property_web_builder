# frozen_string_literal: true

module Pwb
  # Ejecuta el aprovisionamiento de un sitio recién registrado fuera del ciclo
  # de la petición HTTP.
  #
  # Antes, POST /signup/provision corría ProvisioningService de forma síncrona:
  # el sembrado de páginas, contenidos e imágenes tarda minutos (las variantes
  # de imagen se generan con ImageMagick), así que la petición quedaba colgada,
  # la barra de progreso no se movía (el JS recién consultaba el estado DESPUÉS
  # de que respondiera) y si el navegador se iba, el sitio quedaba a medias en
  # un estado intermedio del que no se podía retomar.
  #
  # Ahora el endpoint encola este job y responde al instante; el front consulta
  # /signup/status y ve avanzar el progreso real.
  class ProvisionWebsiteJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    # No reintentar automáticamente: si el aprovisionamiento falla, el sitio
    # queda en estado `failed` con el detalle del error y el usuario reintenta
    # desde la UI (que vuelve a encolar).
    def perform(website_id)
      website = Pwb::Website.unscoped.find(website_id)

      # Idempotencia: si otro job ya lo terminó o lo está corriendo, no duplicar.
      return if website.live? || website.locked?

      Pwb::ProvisioningService.new.provision_website(website: website)
    end
  end
end
