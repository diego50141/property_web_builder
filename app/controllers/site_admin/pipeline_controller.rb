# frozen_string_literal: true

module SiteAdmin
  # Tablero (kanban) de leads/prospectos por etapa. Los leads son Pwb::Contact
  # del website actual. El cambio de etapa y la asignación de agente se hacen por
  # menú (sin drag) para el MVP.
  class PipelineController < SiteAdminController
    before_action -> { require_feature!(:crm) }

    def index
      contacts = current_website.contacts.includes(:assigned_user).to_a
      grouped = contacts.group_by { |c| Pwb::Contact::STAGES.include?(c.stage) ? c.stage : 'nuevo' }
      # Aseguramos todas las etapas presentes (aunque estén vacías).
      @contacts_by_stage = Pwb::Contact::STAGES.index_with { |s| grouped[s] || [] }
      @agents = current_website.users.order(:email)
      @total = contacts.size
      @interest_label = property_interest_labels(contacts)
    end

    def update
      contact = current_website.contacts.find(params[:id])
      attrs = {}
      if params[:stage].present? && Pwb::Contact::STAGES.include?(params[:stage])
        attrs[:stage] = params[:stage]
      end
      attrs[:assigned_user_id] = params[:assigned_user_id].presence if params.key?(:assigned_user_id)
      contact.update(attrs) if attrs.any?

      respond_to do |format|
        format.json { head :ok }
        format.html { redirect_to site_admin_pipeline_path, notice: 'Lead actualizado.' }
      end
    end

    private

    # Devuelve { contact_id => "titulo de la propiedad" } tomando la consulta más
    # reciente de cada contacto que referencia una propiedad.
    def property_interest_labels(contacts)
      ids = contacts.map(&:id)
      return {} if ids.empty?

      latest_asset_by_contact = {}
      Pwb::Message.where(website_id: current_website.id, contact_id: ids)
                  .where.not(realty_asset_id: nil)
                  .order(created_at: :desc)
                  .pluck(:contact_id, :realty_asset_id)
                  .each { |cid, aid| latest_asset_by_contact[cid] ||= aid }

      assets = Pwb::RealtyAsset.where(id: latest_asset_by_contact.values.uniq)
                               .includes(:sale_listings, :rental_listings)
                               .index_by(&:id)

      latest_asset_by_contact.each_with_object({}) do |(cid, aid), acc|
        asset = assets[aid]
        next unless asset

        acc[cid] = asset.sale_listings.first&.title_es ||
                   asset.rental_listings.first&.title_es ||
                   asset.reference
      end
    end
  end
end
