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
      @publish = params[:publish] != "0"

      @result = Pwb::Metrocuadrado::AutoProvisioner.provision(
        agency_url: @url,
        subdomain: @subdomain.presence,
        publish: @publish
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

    # Publica un sitio que quedó en preview (provisioning_state "ready").
    def publish
      website = Pwb::Website.unscoped.find(params[:website_id])

      if website.preview_pending_publish?
        website.publish_preview!
        redirect_to new_tenant_admin_metrocuadrado_provision_path,
                    notice: "Sitio publicado: #{website.subdomain} ya está visible al público."
      else
        redirect_to new_tenant_admin_metrocuadrado_provision_path,
                    alert: "El sitio '#{website.subdomain}' no está en preview (estado: #{website.provisioning_state})."
      end
    end
  end
end
