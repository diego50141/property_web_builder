# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TenantAdmin::MetrocuadradoProvisions', type: :request do
  let(:agency_url) { 'https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157' }
  let(:fixture_path) { Rails.root.join('spec', 'fixtures', 'metrocuadrado') }

  before do
    ENV['BYPASS_ADMIN_AUTH'] = 'true'
  end

  after do
    ENV['BYPASS_ADMIN_AUTH'] = nil
  end

  describe 'GET /tenant_admin/metrocuadrado_provision/new' do
    it 'renders the form' do
      get '/tenant_admin/metrocuadrado_provision/new'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Metrocuadrado')
    end
  end

  describe 'POST /tenant_admin/metrocuadrado_provision' do
    context 'with a valid agency URL' do
      before do
        allow(Pwb::SeedPack).to receive(:find)
          .and_return(instance_double(Pwb::SeedPack, apply!: true))
        stub_request(:get, agency_url)
          .to_return(status: 200, body: File.read(fixture_path.join('agency_page.html')))
        stub_request(:get, %r{\Ahttps://www\.metrocuadrado\.com/inmueble/})
          .to_return(status: 200, body: File.read(fixture_path.join('property_page.html')))
      end

      it 'provisions the website and shows the summary' do
        post '/tenant_admin/metrocuadrado_provision', params: { url: agency_url }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('llanocasa')
        expect(Pwb::Website.unscoped.find_by(subdomain: 'llanocasa')).to be_present
      end
    end

    context 'with an invalid URL' do
      it 'renders the form with an error and provisions nothing' do
        expect do
          post '/tenant_admin/metrocuadrado_provision', params: { url: 'https://otroportal.com/x' }
        end.not_to change(Pwb::Website.unscoped, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'in preview mode (publish unchecked)' do
      before do
        allow(Pwb::SeedPack).to receive(:find)
          .and_return(instance_double(Pwb::SeedPack, apply!: true))
        stub_request(:get, agency_url)
          .to_return(status: 200, body: File.read(fixture_path.join('agency_page.html')))
        stub_request(:get, %r{\Ahttps://www\.metrocuadrado\.com/inmueble/})
          .to_return(status: 200, body: File.read(fixture_path.join('property_page.html')))
      end

      it 'provisions in preview and offers the publish button' do
        post '/tenant_admin/metrocuadrado_provision', params: { url: agency_url, publish: '0' }

        website = Pwb::Website.unscoped.find_by(subdomain: 'llanocasa')
        expect(website.provisioning_state).to eq('ready')
        expect(response.body).to include('preview')
        expect(response.body).to include('Publicar sitio')
      end
    end
  end

  describe 'POST /tenant_admin/metrocuadrado_provision/publish' do
    it 'publishes a preview website' do
      website = FactoryBot.create(:pwb_website, provisioning_state: 'ready')

      post '/tenant_admin/metrocuadrado_provision/publish', params: { website_id: website.id }

      expect(response).to redirect_to('/tenant_admin/metrocuadrado_provision/new')
      expect(website.reload.provisioning_state).to eq('live')
    end

    it 'rejects websites that are not in preview' do
      website = FactoryBot.create(:pwb_website, provisioning_state: 'live')

      post '/tenant_admin/metrocuadrado_provision/publish', params: { website_id: website.id }

      expect(response).to redirect_to('/tenant_admin/metrocuadrado_provision/new')
      expect(flash[:alert]).to include('no está en preview')
    end
  end
end
