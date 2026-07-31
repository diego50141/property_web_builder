# frozen_string_literal: true

module Pwb
  # Ejecuta en background la búsqueda de un Pwb::PropertyRequirement contra
  # Metrocuadrado. Encolado al crear el requerimiento; también puede
  # relanzarse manualmente para refrescar los resultados:
  #   Pwb::RunPropertyRequirementSearchJob.perform_later(requirement_id)
  class RunPropertyRequirementSearchJob < Pwb::ApplicationJob
    queue_as :default

    # Errores transitorios de red: Http ya reintenta por request; si aun así
    # falla el job completo, se reintenta con backoff.
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    discard_on ActiveRecord::RecordNotFound

    def perform(requirement_id)
      requirement = Pwb::PropertyRequirement.find(requirement_id)
      Pwb::PropertyRequirementSearchService.call(requirement)
    end
  end
end
