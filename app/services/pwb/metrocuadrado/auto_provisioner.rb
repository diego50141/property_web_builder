# frozen_string_literal: true

module Pwb
  module Metrocuadrado
    # Fase C del "autopilot": dada la URL de una agencia en Metrocuadrado,
    # crea (o reutiliza) el tenant/website con branding básico y le importa
    # todas sus propiedades.
    #
    #   Pwb::Metrocuadrado::AutoProvisioner.provision(agency_url: "https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157")
    #
    # Pasos:
    #   1. Extrae los datos de la agencia (AgencyExtractor): nombre, logo,
    #      teléfono, dirección, ciudad y slug (candidato a subdominio).
    #   2. Resuelve el subdominio (SubdomainGenerator.validate_custom_name).
    #      Idempotente: si ya existe un website con ese subdominio y el mismo
    #      nombre de agencia, lo reutiliza en vez de fallar.
    #   3. Crea el website "live" con defaults LATAM (locale es, COP) y aplica
    #      el seed pack base (sin propiedades demo ni usuarios demo).
    #   4. Configura Pwb::Agency (nombre, teléfonos, dirección) y el logo
    #      (main_logo_url; Website#logo_url cae a esa columna para los themes).
    #   5. Importa las propiedades con Pwb::Metrocuadrado::Importer.
    #   6. Registra el origen en imports_config (SyncRegistry) para que la
    #      resincronización periódica (ResyncJob) mantenga el sitio al día.
    class AutoProvisioner
      SEED_PACK = "base"
      AGENCY_URL_PATTERN = %r{\Ahttps?://(www\.)?metrocuadrado\.com/inmobiliaria/}i

      Result = Struct.new(:website, :agency_data, :created, :import_results, :error, keyword_init: true) do
        def success? = error.nil?
      end

      # publish: false crea el sitio en preview (provisioning_state "ready"):
      # el público ve "en preparación" y el super-admin lo navega con el
      # preview_token hasta pulsar Publicar (Website#publish_preview!).
      # inline_images: true descarga las fotos en el mismo proceso; necesario
      # desde rake con el adapter :async (ver Importer).
      def self.provision(agency_url:, subdomain: nil, publish: true, inline_images: false)
        new(agency_url, subdomain, publish: publish, inline_images: inline_images).provision
      end

      def initialize(agency_url, subdomain = nil, publish: true, inline_images: false)
        @agency_url = agency_url.to_s.strip
        @subdomain_param = subdomain.to_s.strip.presence
        @publish = publish
        @inline_images = inline_images
      end

      def provision
        unless @agency_url.match?(AGENCY_URL_PATTERN)
          return Result.new(error: "La URL debe ser la página de una agencia (metrocuadrado.com/inmobiliaria/...)")
        end

        agency_data = extract_agency_data
        if agency_data[:property_paths].empty?
          return Result.new(error: "No se encontraron inmuebles en la página de la agencia", agency_data: agency_data)
        end
        if agency_data[:name].blank?
          return Result.new(error: "No se pudo extraer el nombre de la agencia", agency_data: agency_data)
        end

        website, created, subdomain_error = resolve_website(agency_data)
        return Result.new(error: subdomain_error, agency_data: agency_data) if subdomain_error

        configure_website(website, agency_data)
        apply_seed_pack(website) if created
        ActsAsTenant.with_tenant(website) do
          upsert_agency(website, agency_data)
        end

        import_results = Importer.new(website, inline_images: @inline_images).import(@agency_url)
        SyncRegistry.record(website, agency_url: @agency_url, results: import_results)
        Result.new(website: website, agency_data: agency_data, created: created, import_results: import_results)
      rescue StandardError => e
        Rails.logger.error("[metrocuadrado] auto-provisión falló: #{e.class}: #{e.message}")
        Result.new(error: e.message, agency_data: agency_data)
      end

      private

      # Fetches the agency page plus the first property page (which embeds the
      # company block: name, logo, phone, address).
      def extract_agency_data
        agency_html = Http.fetch(@agency_url)
        first_path = AgencyExtractor.new(agency_html).property_paths.first
        property_html = first_path && Http.fetch(Importer::BASE + first_path)
        AgencyExtractor.new(agency_html, property_html).call
      end

      # @return [Array(Pwb::Website, Boolean, String|nil)] website, created?, error
      def resolve_website(agency_data)
        candidate = @subdomain_param ||
                    agency_data[:slug] ||
                    agency_data[:name].to_s.parameterize
        candidate = candidate.downcase.strip

        existing = Pwb::Website.unscoped.find_by(subdomain: candidate)
        if existing
          if same_agency?(existing, agency_data)
            return [existing, false, nil]
          else
            return [nil, false, "El subdominio '#{candidate}' ya está en uso por otro sitio " \
                                "('#{existing.company_display_name}'). Indica otro subdominio."]
          end
        end

        validation = Pwb::SubdomainGenerator.validate_custom_name(candidate)
        unless validation[:valid]
          return [nil, false, "Subdominio '#{candidate}' inválido: #{validation[:errors].join(', ')}"]
        end

        website = Pwb::Website.create!(
          subdomain: validation[:normalized],
          company_display_name: agency_data[:name],
          theme_name: "default",
          # "ready" = preview sin publicar; el estado de un sitio existente
          # nunca se toca al re-provisionar.
          provisioning_state: @publish ? "live" : "ready",
          site_type: "residential",
          seed_pack_name: SEED_PACK
        )
        [website, true, nil]
      end

      def same_agency?(website, agency_data)
        website.company_display_name.to_s.strip.casecmp?(agency_data[:name].to_s.strip)
      end

      # LATAM defaults + branding. Runs on create AND on re-provision so the
      # site stays consistent with the portal data (idempotent).
      def configure_website(website, agency_data)
        website.company_display_name = agency_data[:name]
        website.default_client_locale = "es"
        website.default_admin_locale = "es"
        # Solo español: con un único locale el theme oculta el selector de
        # idioma (el admin puede añadir más luego en ajustes).
        website.supported_locales = %w[es]
        website.default_currency = "COP"
        website.available_currencies = %w[COP USD] if website.respond_to?(:available_currencies=)
        website.supported_currencies = %w[COP USD] if website.respond_to?(:supported_currencies=)
        website.external_image_mode = true
        website.main_logo_url = agency_data[:logo_url] if agency_data[:logo_url]
        if website.selected_palette.blank?
          website.selected_palette = Pwb::Theme.find_by(name: website.theme_name)&.default_palette_id
        end
        website.save!
      end

      def apply_seed_pack(website)
        pack = Pwb::SeedPack.find(SEED_PACK)
        ActsAsTenant.with_tenant(website) do
          Pwb::Current.website = website
          # Sin propiedades ni usuarios demo (las propiedades reales vienen del
          # import); website y agency los configura este servicio.
          pack.apply!(website: website, options: {
                        skip_website: true, skip_agency: true,
                        skip_users: true, skip_properties: true
                      })
        end
      ensure
        Pwb::Current.reset
        ActsAsTenant.current_tenant = nil
      end

      def upsert_agency(website, agency_data)
        agency = website.agency || website.build_agency
        agency.assign_attributes(
          display_name: agency_data[:name],
          company_name: agency_data[:name],
          phone_number_primary: agency_data[:phone],
          phone_number_mobile: agency_data[:whatsapp]
        )
        agency.save!

        return unless agency_data[:city] || agency_data[:street_address]

        address = agency.primary_address || Pwb::Address.new
        address.assign_attributes(
          city: agency_data[:city],
          street_address: agency_data[:street_address],
          country: "Colombia"
        )
        address.save!
        agency.update!(primary_address: address) unless agency.primary_address_id == address.id
      end
    end
  end
end
