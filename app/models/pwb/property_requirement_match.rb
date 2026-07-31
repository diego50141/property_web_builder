# frozen_string_literal: true

module Pwb
  # Una opción externa encontrada para un Pwb::PropertyRequirement.
  # `portal` deja preparado el soporte a más portales sin tocar el esquema;
  # == Schema Information
  #
  # Table name: pwb_property_requirement_matches
  # Database name: primary
  #
  #  id                      :bigint           not null, primary key
  #  area                    :decimal(10, 2)
  #  bathrooms               :integer
  #  bedrooms                :integer
  #  city                    :string
  #  external_reference      :string           not null
  #  matched_at              :datetime
  #  neighborhood            :string
  #  portal                  :string           default("metrocuadrado"), not null
  #  price_cents             :bigint
  #  price_currency          :string           default("COP"), not null
  #  raw_data                :jsonb            not null
  #  source_url              :string
  #  thumbnail_url           :string
  #  title                   :string
  #  created_at              :datetime         not null
  #  updated_at              :datetime         not null
  #  property_requirement_id :bigint           not null
  #
  # Indexes
  #
  #  idx_prop_req_matches_on_requirement  (property_requirement_id)
  #  idx_prop_req_matches_unique          (property_requirement_id,portal,external_reference) UNIQUE
  #
  # por ahora solo existe "metrocuadrado".
  class PropertyRequirementMatch < ApplicationRecord
    self.table_name = 'pwb_property_requirement_matches'

    belongs_to :property_requirement, class_name: 'Pwb::PropertyRequirement', inverse_of: :matches

    validates :portal, presence: true
    validates :external_reference, presence: true, uniqueness: { scope: %i[property_requirement_id portal] }

    monetize :price_cents, with_model_currency: :price_currency, allow_nil: true

    def source_url_full
      return source_url if source_url.to_s.start_with?('http')

      "https://www.metrocuadrado.com#{source_url}"
    end
  end
end
