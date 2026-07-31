# frozen_string_literal: true

# CRM: requerimiento de búsqueda de un cliente (ej. "apto en venta en Bogotá,
# 300-400M, 2 hab, 1 baño") que dispara una búsqueda en portales externos
# (Metrocuadrado). Los resultados van en pwb_property_requirement_matches,
# no en pwb_realty_assets: no son inventario propio.
class CreatePwbPropertyRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :pwb_property_requirements do |t|
      t.bigint :website_id, null: false
      t.bigint :contact_id
      t.bigint :created_by_id

      # Vocabulario alineado al de la API de Metrocuadrado (venta/arriendo,
      # apartamento/casa/...) para no necesitar una capa de traducción.
      t.string :operation_type, null: false, default: 'venta'
      t.string :property_type_key, null: false, default: 'apartamento'
      t.string :city
      t.string :city_slug

      t.bigint :price_min_cents
      t.bigint :price_max_cents
      t.string :price_currency, null: false, default: 'COP'
      t.integer :bedrooms_min
      t.integer :bathrooms_min

      t.string :status, null: false, default: 'pending'
      t.datetime :last_searched_at
      t.integer :results_count, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :pwb_property_requirements, :website_id
    add_index :pwb_property_requirements, :contact_id
    add_index :pwb_property_requirements, :status
  end
end
