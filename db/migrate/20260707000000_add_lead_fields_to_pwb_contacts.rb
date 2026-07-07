# frozen_string_literal: true

# CRM Fase 2: convierte Pwb::Contact en el "lead" del pipeline añadiendo etapa,
# fuente y agente asignado.
class AddLeadFieldsToPwbContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :pwb_contacts, :stage, :string, default: 'nuevo', null: false
    add_column :pwb_contacts, :source, :string
    add_column :pwb_contacts, :assigned_user_id, :integer

    add_index :pwb_contacts, :stage
    add_index :pwb_contacts, :assigned_user_id
    add_index :pwb_contacts, %i[website_id stage]
  end
end
