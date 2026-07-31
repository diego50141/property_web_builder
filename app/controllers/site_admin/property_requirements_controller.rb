# frozen_string_literal: true

module SiteAdmin
  # Requerimientos de búsqueda de clientes contra portales externos
  # (Metrocuadrado): el agente carga el criterio (operación, ciudad, precio,
  # mínimos) y un job busca en el portal; los resultados quedan como
  # PropertyRequirementMatch y se muestran en el show.
  class PropertyRequirementsController < SiteAdminController
    before_action -> { require_feature!(:crm) }

    # Ciudades verificadas contra el portal (ver Pwb::Metrocuadrado::CityMapper):
    # el form solo ofrece estas para que una búsqueda nunca falle por slug.
    CITY_OPTIONS = ['Bogotá', 'Medellín', 'Cali', 'Cartagena', 'Barranquilla',
                    'Bucaramanga', 'Pereira', 'Santa Marta', 'Villavicencio'].freeze

    # Tipos de inmueble en el vocabulario del portal (realEstateTypeList).
    PROPERTY_TYPE_OPTIONS = [
      %w[Apartamento apartamento],
      %w[Apartaestudio apartaestudio],
      %w[Casa casa],
      %w[Oficina oficina],
      ['Local comercial', 'local'],
      %w[Lote lote],
      %w[Finca finca],
      %w[Bodega bodega]
    ].freeze

    def index
      @requirements = current_website.property_requirements
                                     .includes(:contact)
                                     .order(created_at: :desc)
                                     .limit(100)
    end

    def show
      @requirement = current_website.property_requirements.includes(:contact).find(params.expect(:id))
      @matches = @requirement.matches.order(price_cents: :asc)
    end

    def new
      @requirement = current_website.property_requirements.new(
        operation_type: 'venta', property_type_key: 'apartamento'
      )
      load_form_collections
    end

    def create
      @requirement = current_website.property_requirements.new(requirement_params)
      @requirement.created_by_id = current_user&.id
      @requirement.city_slug = Pwb::Metrocuadrado::CityMapper.slug_for(@requirement.city)

      if @requirement.save
        Pwb::RunPropertyRequirementSearchJob.perform_later(@requirement.id)
        redirect_to site_admin_property_requirement_path(@requirement),
                    notice: 'Búsqueda creada. Los resultados aparecerán en unos segundos.'
      else
        load_form_collections
        render :new, status: :unprocessable_content
      end
    end

    def rerun
      requirement = current_website.property_requirements.find(params.expect(:id))
      requirement.update!(status: 'pending')
      Pwb::RunPropertyRequirementSearchJob.perform_later(requirement.id)
      redirect_to site_admin_property_requirement_path(requirement),
                  notice: 'Búsqueda relanzada. Los resultados se actualizarán en unos segundos.'
    end

    def destroy
      requirement = current_website.property_requirements.find(params.expect(:id))
      requirement.destroy
      redirect_to site_admin_property_requirements_path, notice: 'Búsqueda eliminada.'
    end

    private

    def load_form_collections
      @contacts = current_website.contacts.order(:first_name, :last_name)
      @city_options = CITY_OPTIONS
      @property_type_options = PROPERTY_TYPE_OPTIONS
    end

    # El agente escribe precios en pesos; el modelo los guarda en centavos.
    def requirement_params
      permitted = params
                  .expect(property_requirement: %i[contact_id operation_type property_type_key city
                                                   bedrooms_min bathrooms_min])
      permitted[:price_min_cents] = pesos_to_cents(params[:property_requirement][:price_min])
      permitted[:price_max_cents] = pesos_to_cents(params[:property_requirement][:price_max])
      permitted
    end

    def pesos_to_cents(value)
      digits = value.to_s.gsub(/[^\d]/, '')
      digits.blank? ? nil : digits.to_i * 100
    end
  end
end
