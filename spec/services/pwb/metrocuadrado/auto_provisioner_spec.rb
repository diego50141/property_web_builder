# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe AutoProvisioner do
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

      describe '.provision' do
        it 'creates a live website with LATAM defaults and the agency branding' do
          result = described_class.provision(agency_url: agency_url)

          expect(result).to be_success
          expect(result.created).to be(true)

          website = result.website.reload
          expect(website.subdomain).to eq('llanocasa')
          expect(website.company_display_name).to eq('LLANOCASA')
          expect(website.provisioning_state).to eq('live')
          expect(website.default_currency).to eq('COP')
          expect(website.default_client_locale).to eq('es')
          expect(website.supported_locales).to include('es')
          expect(website.external_image_mode).to be(true)
          expect(website.main_logo_url)
            .to eq('https://www.metrocuadrado.com/files/logos/company/7157/company7157.png')
        end

        it 'configures the agency contact data from the portal' do
          result = described_class.provision(agency_url: agency_url)

          agency = result.website.reload.agency
          expect(agency.display_name).to eq('LLANOCASA')
          expect(agency.phone_number_primary).to eq('3017891932')
          expect(agency.phone_number_mobile).to eq('573017891932')
          expect(agency.primary_address.city).to eq('Villavicencio')
          expect(agency.primary_address.street_address).to eq('Cra 44A # 12A - 12')
        end

        it 'applies the base seed pack without demo properties, users, website or agency' do
          described_class.provision(agency_url: agency_url)

          expect(seed_pack_double).to have_received(:apply!).with(
            website: kind_of(Pwb::Website),
            options: hash_including(
              skip_website: true, skip_agency: true,
              skip_users: true, skip_properties: true
            )
          )
        end

        it 'imports the agency properties into the new tenant' do
          result = described_class.provision(agency_url: agency_url)

          imported = result.import_results.select { |r| r.action == 'imported' }
          expect(imported.length).to eq(3)
          expect(Pwb::RealtyAsset.unscoped.where(website_id: result.website.id).count).to eq(3)
        end

        it 'honours an explicit subdomain' do
          result = described_class.provision(agency_url: agency_url, subdomain: 'llano-custom')

          expect(result).to be_success
          expect(result.website.subdomain).to eq('llano-custom')
        end

        it 'is idempotent: re-running for the same agency reuses the website' do
          first = described_class.provision(agency_url: agency_url)

          second = nil
          expect do
            second = described_class.provision(agency_url: agency_url)
          end.not_to change(Pwb::Website.unscoped, :count)

          expect(second).to be_success
          expect(second.created).to be(false)
          expect(second.website.id).to eq(first.website.id)
        end

        it 'does not duplicate properties when re-run (upsert by reference)' do
          described_class.provision(agency_url: agency_url)
          result = described_class.provision(agency_url: agency_url)

          expect(Pwb::RealtyAsset.unscoped.where(website_id: result.website.id).count).to eq(3)
        end

        it 'refuses to reuse a subdomain that belongs to a different agency' do
          FactoryBot.create(:pwb_website, subdomain: 'llanocasa',
                                          company_display_name: 'Otra Inmobiliaria')

          result = described_class.provision(agency_url: agency_url)

          expect(result).not_to be_success
          expect(result.error).to include('ya está en uso')
          expect(result.website).to be_nil
        end

        it 'rejects URLs that are not an agency page' do
          result = described_class.provision(
            agency_url: 'https://www.metrocuadrado.com/inmueble/venta-casa/123-M99'
          )

          expect(result).not_to be_success
          expect(result.error).to include('inmobiliaria')
        end

        it 'returns an error when the agency page has no listings' do
          stub_request(:get, agency_url)
            .to_return(status: 200, body: '<html><body>sin resultados</body></html>')

          result = described_class.provision(agency_url: agency_url)

          expect(result).not_to be_success
          expect(result.error).to include('No se encontraron inmuebles')
        end

        it 'returns an error result instead of raising when the portal is down' do
          stub_request(:get, agency_url).to_return(status: 503)

          result = described_class.provision(agency_url: agency_url)

          expect(result).not_to be_success
          expect(result.error).to include('503')
        end
      end
    end
  end
end
