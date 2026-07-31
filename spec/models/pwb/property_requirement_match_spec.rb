# frozen_string_literal: true

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
require 'rails_helper'

module Pwb
  RSpec.describe PropertyRequirementMatch do
    let(:website) { FactoryBot.create(:pwb_website) }
    let(:requirement) { FactoryBot.create(:pwb_property_requirement, website: website) }

    it 'requires external_reference to be unique per requirement and portal' do
      requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1')
      duplicate = requirement.matches.build(portal: 'metrocuadrado', external_reference: 'ABC-1')

      expect(duplicate).not_to be_valid
    end

    it 'allows the same external_reference on a different requirement' do
      other = FactoryBot.create(:pwb_property_requirement, website: website)
      requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1')
      elsewhere = other.matches.build(portal: 'metrocuadrado', external_reference: 'ABC-1')

      expect(elsewhere).to be_valid
    end

    describe '#source_url_full' do
      it 'prefixes the portal host when the stored url is relative' do
        match = requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1',
                                             source_url: '/inmueble/venta-apartamento/ABC-1')
        expect(match.source_url_full).to eq('https://www.metrocuadrado.com/inmueble/venta-apartamento/ABC-1')
      end

      it 'leaves an already-absolute url untouched' do
        full_url = 'https://www.metrocuadrado.com/proyecto/foo/ABC-1'
        match = requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1', source_url: full_url)
        expect(match.source_url_full).to eq(full_url)
      end
    end

    describe 'price' do
      it 'monetizes price_cents in COP' do
        match = requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1', price_cents: 350_000_000_00)
        expect(match.price.cents).to eq(350_000_000_00)
        expect(match.price.currency.iso_code).to eq('COP')
      end
    end
  end
end
