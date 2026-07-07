# frozen_string_literal: true

module Pwb
  # Enlace entre un cliente (Contact) y un inmueble (RealtyAsset).
  class ContactRealtyAsset < ApplicationRecord
    self.table_name = 'pwb_contact_realty_assets'

    belongs_to :contact, class_name: 'Pwb::Contact'
    belongs_to :realty_asset, class_name: 'Pwb::RealtyAsset'
    belongs_to :website, class_name: 'Pwb::Website', optional: true
  end
end
