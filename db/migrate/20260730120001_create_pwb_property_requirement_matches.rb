# frozen_string_literal: true

# Una fila por opción externa encontrada para un Pwb::PropertyRequirement.
# `portal` deja preparado el soporte a más portales además de Metrocuadrado
# sin tocar el esquema. Idempotente por [requirement_id, portal, external_reference].
class CreatePwbPropertyRequirementMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :pwb_property_requirement_matches do |t|
      t.bigint :property_requirement_id, null: false
      t.string :portal, null: false, default: 'metrocuadrado'
      t.string :external_reference, null: false
      t.string :source_url

      t.string :title
      t.bigint :price_cents
      t.string :price_currency, null: false, default: 'COP'
      t.integer :bedrooms
      t.integer :bathrooms
      t.decimal :area, precision: 10, scale: 2
      t.string :city
      t.string :neighborhood
      t.string :thumbnail_url

      t.jsonb :raw_data, null: false, default: {}
      t.datetime :matched_at

      t.timestamps
    end

    add_index :pwb_property_requirement_matches, :property_requirement_id,
              name: 'idx_prop_req_matches_on_requirement'
    add_index :pwb_property_requirement_matches, %i[property_requirement_id portal external_reference],
              unique: true, name: 'idx_prop_req_matches_unique'
  end
end
