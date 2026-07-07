# frozen_string_literal: true

# CRM: enlaza clientes (Pwb::Contact) con inmuebles (Pwb::RealtyAsset).
class CreatePwbContactRealtyAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :pwb_contact_realty_assets do |t|
      t.bigint :contact_id, null: false
      t.uuid :realty_asset_id, null: false
      t.bigint :website_id
      t.string :relationship, default: 'interes'
      t.timestamps
    end

    add_index :pwb_contact_realty_assets, :contact_id
    add_index :pwb_contact_realty_assets, :realty_asset_id
    add_index :pwb_contact_realty_assets, %i[contact_id realty_asset_id],
              unique: true, name: 'idx_contact_realty_unique'
  end
end
