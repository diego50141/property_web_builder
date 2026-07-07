# frozen_string_literal: true

module TenantAdmin
  # Auto-provisión de un tenant desde una agencia de Metrocuadrado (Fase C
  # del autopilot): pega el link de la agencia -> se crea el sitio con
  # branding básico y se importan sus propiedades.
  class MetrocuadradoProvisionsController < TenantAdminController
    def new; end

    def create
      @url = params[:url].to_s.strip
      @subdomain = params[:subdomain].to_s.strip

      @result = Pwb::Metrocuadrado::AutoProvisioner.provision(
        agency_url: @url,
        subdomain: @subdomain.presence
      )

      if @result.success?
        imported = @result.import_results.count { |r| r.action == "imported" }
        flash.now[:notice] = "#{@result.created ? 'Sitio creado' : 'Sitio actualizado'}: " \
                             "#{@result.website.subdomain} (#{imported} propiedades importadas)"
        render :new
      else
        flash.now[:alert] = @result.error
        render :new, status: :unprocessable_entity
      end
    end
  end
end
