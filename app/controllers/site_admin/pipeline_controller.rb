# frozen_string_literal: true

module SiteAdmin
  # Tablero (kanban) de leads/prospectos por etapa. Los leads son Pwb::Contact
  # del website actual. El cambio de etapa y la asignación de agente se hacen por
  # menú (sin drag) para el MVP.
  class PipelineController < SiteAdminController
    def index
      contacts = current_website.contacts.includes(:assigned_user)
      grouped = contacts.group_by { |c| Pwb::Contact::STAGES.include?(c.stage) ? c.stage : 'nuevo' }
      # Aseguramos todas las etapas presentes (aunque estén vacías).
      @contacts_by_stage = Pwb::Contact::STAGES.index_with { |s| grouped[s] || [] }
      @agents = current_website.users.order(:email)
      @total = contacts.size
    end

    def update
      contact = current_website.contacts.find(params[:id])
      attrs = {}
      if params[:stage].present? && Pwb::Contact::STAGES.include?(params[:stage])
        attrs[:stage] = params[:stage]
      end
      attrs[:assigned_user_id] = params[:assigned_user_id].presence if params.key?(:assigned_user_id)
      contact.update(attrs) if attrs.any?

      redirect_to site_admin_pipeline_path, notice: 'Lead actualizado.'
    end
  end
end
