# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe SyncRegistry do
      let(:agency_url) { 'https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157' }
      let(:website) { FactoryBot.create(:pwb_website) }
      let(:results) do
        [
          Importer::Result.new(reference: '4321-M1', action: 'imported', photos: 2),
          Importer::Result.new(reference: '4321-M2', action: 'imported', photos: 0),
          Importer::Result.new(reference: '4321-M3', action: 'error', error: 'boom'),
          Importer::Result.new(reference: nil, action: 'skipped', error: 'sin reference')
        ]
      end

      describe '.record' do
        it 'stores the agency url, timestamp and summary in imports_config' do
          described_class.record(website, agency_url: agency_url, results: results)

          entry = website.reload.imports_config['metrocuadrado']
          expect(entry['agency_url']).to eq(agency_url)
          expect(entry['auto_resync']).to be(true)
          expect(entry['last_synced_at']).to be_present
          expect(entry['last_result']).to eq('imported' => 2, 'errors' => 1, 'skipped' => 1)
        end

        it 'does not re-enable auto_resync when it was turned off' do
          website.update!(imports_config: { 'metrocuadrado' => { 'auto_resync' => false } })

          described_class.record(website, agency_url: agency_url, results: results)

          expect(website.reload.imports_config.dig('metrocuadrado', 'auto_resync')).to be(false)
        end

        it 'preserves unrelated imports_config entries' do
          website.update!(imports_config: { 'otra_fuente' => { 'x' => 1 } })

          described_class.record(website, agency_url: agency_url, results: results)

          expect(website.reload.imports_config['otra_fuente']).to eq('x' => 1)
        end
      end

      describe '.resyncable_websites' do
        it 'returns only operative websites with auto_resync enabled' do
          enabled = FactoryBot.create(:pwb_website)
          described_class.record(enabled, agency_url: agency_url, results: results)

          disabled = FactoryBot.create(:pwb_website)
          disabled.update!(imports_config: {
                             'metrocuadrado' => { 'agency_url' => agency_url, 'auto_resync' => false }
                           })

          suspended = FactoryBot.create(:pwb_website)
          described_class.record(suspended, agency_url: agency_url, results: results)
          suspended.update!(provisioning_state: 'suspended')

          no_registry = FactoryBot.create(:pwb_website)

          ids = described_class.resyncable_websites.pluck(:id)
          expect(ids).to include(enabled.id)
          expect(ids).not_to include(disabled.id, suspended.id, no_registry.id)
        end
      end
    end
  end
end
