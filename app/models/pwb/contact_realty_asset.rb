# frozen_string_literal: true

module Pwb
# == Schema Information
#
# Table name: pwb_contact_realty_assets
# Database name: primary
#
#  id              :bigint           not null, primary key
#  relationship    :string           default("interes")
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  contact_id      :bigint           not null
#  realty_asset_id :uuid             not null
#  website_id      :bigint
#
# Indexes
#
#  idx_contact_realty_unique                           (contact_id,realty_asset_id) UNIQUE
#  index_pwb_contact_realty_assets_on_contact_id       (contact_id)
#  index_pwb_contact_realty_assets_on_realty_asset_id  (realty_asset_id)
#
  # Enlace entre un cliente (Contact) y un inmueble (RealtyAsset).
  class ContactRealtyAsset < ApplicationRecord
    self.table_name = 'pwb_contact_realty_assets'

    belongs_to :contact, class_name: 'Pwb::Contact'
    belongs_to :realty_asset, class_name: 'Pwb::RealtyAsset'
    belongs_to :website, class_name: 'Pwb::Website', optional: true
  end
end
