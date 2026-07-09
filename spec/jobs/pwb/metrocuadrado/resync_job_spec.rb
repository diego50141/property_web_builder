# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pwb::Metrocuadrado::ResyncJob, type: :job do
  let(:fixture_path) { Rails.root.join('spec', 'fixtures', 'metrocuadrado') }
  let(:agency_html) { File.read(fixture_path.join('agency_page.html')) }
  let(:property_html) { File.read(fixture_path.join('property_page.html')) }
  let(:agency_url) { 'https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157' }
  let(:seed_pack_double) { instance_double(Pwb::SeedPack, apply!: true) }

  before do
    allow(Pwb::SeedPack).to receive(:find).and_return(seed_pack_double)
    stub_request(:get, agency_url).to_return(status: 200, body: agency_html)
    stub_request(:get, %r{\Ahttps://www\.metrocuadrado\.com/inmueble/})
      .to_return(status: 200, body: property_html)
  end

  def provisioned_website
    Pwb::Metrocuadrado::AutoProvisioner.provision(agency_url: agency_url).website
  end

  def clear_last_synced_at(website)
    config = website.reload.imports_config
    config['metrocuadrado']['last_synced_at'] = nil
    website.update!(imports_config: config)
  end

  it 're-imports the properties and refreshes the sync registry' do
    website = provisioned_website
    Pwb::RealtyAsset.unscoped.where(website_id: website.id).first.destroy!
    clear_last_synced_at(website)

    described_class.perform_now

    expect(Pwb::RealtyAsset.unscoped.where(website_id: website.id).count).to eq(3)
    entry = website.reload.imports_config['metrocuadrado']
    expect(entry['last_synced_at']).to be_present
    expect(entry['last_result']['imported']).to eq(3)
  end

  it 'only touches the requested website when website_id is given' do
    website = provisioned_website
    clear_last_synced_at(website)

    described_class.perform_now(website_id: website.id + 1)

    expect(website.reload.imports_config.dig('metrocuadrado', 'last_synced_at')).to be_nil
  end

  it 'skips websites with auto_resync disabled' do
    website = provisioned_website
    config = website.reload.imports_config
    config['metrocuadrado']['auto_resync'] = false
    config['metrocuadrado']['last_synced_at'] = nil
    website.update!(imports_config: config)

    described_class.perform_now

    expect(website.reload.imports_config.dig('metrocuadrado', 'last_synced_at')).to be_nil
  end

  it 'keeps going when one website fails to sync' do
    broken_url = 'https://www.metrocuadrado.com/inmobiliaria/rota/999'
    stub_request(:get, broken_url).to_return(status: 500)
    broken = FactoryBot.create(:pwb_website)
    broken.update!(imports_config: {
                     'metrocuadrado' => { 'agency_url' => broken_url, 'auto_resync' => true }
                   })

    website = provisioned_website
    clear_last_synced_at(website)

    expect { described_class.perform_now }.not_to raise_error

    expect(website.reload.imports_config.dig('metrocuadrado', 'last_synced_at')).to be_present
  end
end
