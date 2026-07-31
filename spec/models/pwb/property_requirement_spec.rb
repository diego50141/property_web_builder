# frozen_string_literal: true

# == Schema Information
#
# Table name: pwb_property_requirements
# Database name: primary
#
#  id                :bigint           not null, primary key
#  bathrooms_min     :integer
#  bedrooms_min      :integer
#  city              :string
#  city_slug         :string
#  error_message     :text
#  last_searched_at  :datetime
#  operation_type    :string           default("venta"), not null
#  price_currency    :string           default("COP"), not null
#  price_max_cents   :bigint
#  price_min_cents   :bigint
#  property_type_key :string           default("apartamento"), not null
#  results_count     :integer          default(0), not null
#  status            :string           default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  contact_id        :bigint
#  created_by_id     :bigint
#  website_id        :bigint           not null
#
# Indexes
#
#  index_pwb_property_requirements_on_contact_id  (contact_id)
#  index_pwb_property_requirements_on_status      (status)
#  index_pwb_property_requirements_on_website_id  (website_id)
#
require 'rails_helper'

module Pwb
  RSpec.describe PropertyRequirement do
    let(:website) { FactoryBot.create(:pwb_website) }

    describe 'validations' do
      it 'is valid with the factory defaults' do
        expect(FactoryBot.build(:pwb_property_requirement, website: website)).to be_valid
      end

      it 'rejects an unknown operation_type' do
        requirement = FactoryBot.build(:pwb_property_requirement, website: website, operation_type: 'permuta')
        expect(requirement).not_to be_valid
      end

      it 'requires a city' do
        requirement = FactoryBot.build(:pwb_property_requirement, website: website, city: nil)
        expect(requirement).not_to be_valid
      end

      it 'rejects a max price lower than the min price' do
        requirement = FactoryBot.build(:pwb_property_requirement, website: website,
                                       price_min_cents: 400_000_000_00, price_max_cents: 300_000_000_00)
        expect(requirement).not_to be_valid
        expect(requirement.errors[:price_max_cents]).to be_present
      end

      it 'allows an open-ended range (only min or only max present)' do
        requirement = FactoryBot.build(:pwb_property_requirement, website: website,
                                       price_min_cents: 300_000_000_00, price_max_cents: nil)
        expect(requirement).to be_valid
      end
    end

    describe '#sale? / #rent?' do
      it 'reflects operation_type' do
        sale = FactoryBot.build(:pwb_property_requirement, website: website)
        rent = FactoryBot.build(:pwb_property_requirement, :rent, website: website)

        expect(sale.sale?).to be(true)
        expect(sale.rent?).to be(false)
        expect(rent.rent?).to be(true)
      end
    end

    describe 'status transitions' do
      let(:requirement) { FactoryBot.create(:pwb_property_requirement, website: website) }

      it '#mark_running! sets status to running' do
        requirement.mark_running!
        expect(requirement.reload.status).to eq('running')
      end

      it '#mark_completed! records the result count and timestamp' do
        requirement.mark_completed!(count: 5)
        requirement.reload
        expect(requirement.status).to eq('completed')
        expect(requirement.results_count).to eq(5)
        expect(requirement.last_searched_at).to be_present
        expect(requirement.error_message).to be_nil
      end

      it '#mark_failed! records a truncated error message' do
        requirement.mark_failed!('boom')
        requirement.reload
        expect(requirement.status).to eq('failed')
        expect(requirement.error_message).to eq('boom')
      end
    end

    describe 'associations' do
      it 'destroys matches when the requirement is destroyed' do
        requirement = FactoryBot.create(:pwb_property_requirement, website: website)
        requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1')

        expect { requirement.destroy }.to change(Pwb::PropertyRequirementMatch, :count).by(-1)
      end

      it 'nullifies contact_id when the linked contact is destroyed' do
        contact = FactoryBot.create(:pwb_contact, website: website)
        requirement = FactoryBot.create(:pwb_property_requirement, website: website, contact: contact)

        contact.destroy

        expect(requirement.reload.contact_id).to be_nil
      end
    end
  end
end
