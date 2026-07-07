# frozen_string_literal: true

module SiteAdmin
  # ContactsController
  # Manages contacts for the current website
  class ContactsController < SiteAdminController
    include SiteAdminIndexable

    indexable_config model: Pwb::Contact,
                     search_columns: %i[primary_email first_name last_name],
                     limit: 100

    def new
      @contact = current_website.contacts.new(stage: 'nuevo')
      @contact.assigned_user_id ||= current_user&.id
      load_form_collections
    end

    def create
      @contact = current_website.contacts.new(contact_params)
      @contact.stage = 'nuevo' if @contact.stage.blank?
      @contact.source = @contact.source.presence || 'manual'
      @contact.primary_address = Pwb::Address.new(address_params) if address_filled?
      @contact.details = (@contact.details || {}).merge(detail_params)

      if @contact.save
        link_properties(@contact)
        redirect_to site_admin_contact_path(@contact),
                    notice: "Cliente \"#{[@contact.first_name, @contact.last_name].join(' ').strip.presence || @contact.primary_email}\" creado."
      else
        load_form_collections
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @contact = current_website.contacts.find(params[:id])
      load_form_collections
    end

    def update
      @contact = current_website.contacts.find(params[:id])
      @contact.assign_attributes(contact_params)
      @contact.source = @contact.source.presence || 'manual'
      if address_filled?
        (@contact.primary_address || @contact.build_primary_address).assign_attributes(address_params)
      end
      @contact.details = (@contact.details || {}).merge(detail_params)

      if @contact.save
        sync_linked_properties(@contact)
        redirect_to site_admin_contact_path(@contact), notice: 'Cliente actualizado.'
      else
        load_form_collections
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def load_form_collections
      @agents = current_website.users.order(:email)
      @property_options = current_website.realty_assets
                                         .includes(:sale_listings, :rental_listings)
                                         .map do |a|
        title = a.sale_listings.first&.title_es || a.rental_listings.first&.title_es || a.reference
        [title, a.id]
      end
    end

    def link_properties(contact)
      Array(params[:linked_property_ids]).reject(&:blank?).uniq.each do |asset_id|
        contact.contact_realty_assets.create(realty_asset_id: asset_id, website_id: current_website.id)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        next
      end
    end

    # Reemplaza el conjunto de inmuebles enlazados por los enviados en el form.
    def sync_linked_properties(contact)
      ids = Array(params[:linked_property_ids]).reject(&:blank?).uniq
      contact.contact_realty_assets.where.not(realty_asset_id: ids).destroy_all
      existing = contact.contact_realty_assets.pluck(:realty_asset_id).map(&:to_s)
      (ids - existing).each do |asset_id|
        contact.contact_realty_assets.create(realty_asset_id: asset_id, website_id: current_website.id)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        next
      end
    end

    def contact_params
      params.require(:contact).permit(:first_name, :last_name, :primary_email,
                                      :primary_phone_number, :other_phone_number,
                                      :documentation_id, :assigned_user_id, :source)
    end

    def address_params
      params.fetch(:address, {}).permit(:country, :region, :city, :street_address)
    end

    def address_filled?
      address_params.values.any?(&:present?)
    end

    def detail_params
      params.fetch(:details, {}).permit(:tipo_cliente, :fecha_nacimiento, :etiqueta,
                                        :embudo, :referido, :datos_adicionales,
                                        :observaciones, :acepta_correos).to_h
    end
  end
end
