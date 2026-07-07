# frozen_string_literal: true

module SiteAdmin
  # Importa propiedades desde una URL de Metrocuadrado hacia el website actual.
  # Acepta la página de una agencia (/inmobiliaria/...) o de una propiedad
  # individual (/inmueble/...). La importación corre en la misma petición y
  # muestra el resumen de resultados.
  class MetrocuadradoImportController < SiteAdminController
    URL_RE = %r{\Ahttps?://(www\.)?metrocuadrado\.com/}i

    def new
      @results = nil
    end

    def create
      @url = params[:url].to_s.strip

      unless @url.match?(URL_RE)
        flash.now[:alert] = "Ingresa una URL válida de Metrocuadrado (página de agencia o de propiedad)."
        return render :new, status: :unprocessable_entity
      end

      current_website.update!(external_image_mode: true) unless current_website.external_image_mode
      @results = Pwb::Metrocuadrado::Importer.new(current_website).import(@url)
      Rails.cache.clear

      @imported = @results.count { |r| r.action == "imported" }
      @errored  = @results.count { |r| r.action == "error" }
      flash.now[:notice] = "Se importaron #{@imported} propiedad(es) desde Metrocuadrado."
      render :new
    rescue StandardError => e
      flash.now[:alert] = "No se pudo importar: #{e.message}"
      @results = nil
      render :new, status: :unprocessable_entity
    end
  end
end
