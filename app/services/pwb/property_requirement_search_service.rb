# frozen_string_literal: true

module Pwb
  # Orquesta la búsqueda de un Pwb::PropertyRequirement contra los portales
  # soportados (Metrocuadrado y Fincaraíz). Cada portal tiene su SearchClient
  # con la misma interfaz (city_slug_for / search_all / normalize); acá se
  # filtra por mínimos en Ruby (Metrocuadrado no sabe filtrar "N o más"),
  # se upsertan los PropertyRequirementMatch por [portal, external_reference]
  # y se eliminan los matches que ya no aparecen (por portal).
  #
  # Un portal caído no frena al otro: el requirement queda "completed" con
  # una nota en error_message si algún portal falló, y "failed" solo cuando
  # fallan todos.
  class PropertyRequirementSearchService
    PORTALS = {
      'metrocuadrado' => Pwb::Metrocuadrado::SearchClient,
      'fincaraiz' => Pwb::Fincaraiz::SearchClient
    }.freeze

    def self.call(requirement)
      new(requirement).call
    end

    def initialize(requirement)
      @requirement = requirement
    end

    def call
      @requirement.mark_running!

      portal_errors = {}
      searched_any = false

      PORTALS.each do |portal, client|
        city_slug = resolve_city_slug(portal, client)
        if city_slug.blank?
          portal_errors[portal] = "ciudad \"#{@requirement.city}\" no soportada"
          next
        end

        begin
          sync_portal(portal, client, city_slug)
          searched_any = true
        rescue StandardError => e
          Rails.logger.error(
            "[PropertyRequirementSearchService] requirement ##{@requirement.id} #{portal} falló: #{e.class}: #{e.message}"
          )
          portal_errors[portal] = e.message
        end
      end

      finish(searched_any, portal_errors)
      @requirement
    end

    private

    # El city_slug guardado en el requirement es el de Metrocuadrado (legacy);
    # para el resto de portales siempre se resuelve desde el nombre.
    def resolve_city_slug(portal, client)
      return @requirement.city_slug.presence || client.city_slug_for(@requirement.city) if portal == 'metrocuadrado'

      client.city_slug_for(@requirement.city)
    end

    def sync_portal(portal, client, city_slug)
      raw_results = client.search_all(
        operation_type: @requirement.operation_type,
        property_type_key: @requirement.property_type_key,
        city_slug: city_slug,
        price_min_cents: @requirement.price_min_cents,
        price_max_cents: @requirement.price_max_cents,
        bedrooms_min: @requirement.bedrooms_min,
        bathrooms_min: @requirement.bathrooms_min
      )

      matched = raw_results.map { |item| client.normalize(item, rent: @requirement.rent?) }
                           .select { |result| meets_minimums?(result) }
                           .reject { |result| result[:reference].blank? }

      upsert_matches(portal, matched)
      prune_stale(portal, matched)
    end

    def meets_minimums?(result)
      return false if @requirement.bedrooms_min.present? && result[:bedrooms] < @requirement.bedrooms_min
      return false if @requirement.bathrooms_min.present? && result[:bathrooms] < @requirement.bathrooms_min

      true
    end

    def upsert_matches(portal, results)
      results.each do |result|
        match = @requirement.matches.find_or_initialize_by(portal: portal, external_reference: result[:reference])
        match.assign_attributes(
          source_url: result[:source_url],
          title: result[:title],
          price_cents: result[:price_cents],
          bedrooms: result[:bedrooms],
          bathrooms: result[:bathrooms],
          area: result[:area],
          city: result[:city],
          neighborhood: result[:neighborhood],
          thumbnail_url: result[:thumbnail_url],
          raw_data: result[:raw],
          matched_at: Time.current
        )
        match.save!
      end
    end

    # Los matches de corridas anteriores que ya no vienen en esta búsqueda
    # (el anuncio se retiró, cambió de precio fuera de rango, etc.) se
    # eliminan: cada corrida refleja el estado actual del portal, no un
    # historial acumulado. Solo se poda el portal recién sincronizado.
    def prune_stale(portal, matched)
      seen = matched.map { |result| result[:reference] }
      @requirement.matches.where(portal: portal).where.not(external_reference: seen).destroy_all
    end

    def finish(searched_any, portal_errors)
      unless searched_any
        @requirement.mark_failed!(format_errors(portal_errors).presence || 'No se pudo buscar en ningún portal')
        return
      end

      @requirement.mark_completed!(count: @requirement.matches.count)
      # Nota de fallo parcial: completed, pero dejando rastro del portal caído.
      @requirement.update!(error_message: format_errors(portal_errors)) if portal_errors.any?
    end

    def format_errors(portal_errors)
      portal_errors.map { |portal, msg| "#{portal}: #{msg}" }.join(' | ').truncate(500)
    end
  end
end
