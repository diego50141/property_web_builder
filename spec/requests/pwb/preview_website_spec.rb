# frozen_string_literal: true

require 'rails_helper'

module Pwb
  RSpec.describe 'Preview websites (Fase D autopilot)', type: :request do
    include FactoryBot::Syntax::Methods

    before(:each) do
      Pwb::Current.reset
    end

    let!(:website) do
      create(:pwb_website, subdomain: 'preview-test', provisioning_state: 'ready')
    end
    let!(:page) do
      ActsAsTenant.with_tenant(website) do
        create(:pwb_page, slug: 'home', website: website, visible: true)
      end
    end

    before { host! 'preview-test.example.com' }

    it 'shows the "en preparación" page to the public (404)' do
      get '/'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Sitio en preparación')
    end

    it 'rejects an invalid preview token' do
      get '/', params: { preview_token: 'nope' }

      expect(response).to have_http_status(:not_found)
    end

    it 'grants access with the preview token and keeps it in the session' do
      get '/', params: { preview_token: website.preview_token }
      expect(response).to have_http_status(:success)

      get '/'
      expect(response).to have_http_status(:success)
    end

    it 'serves the site normally once published' do
      website.publish_preview!

      get '/'

      expect(response).to have_http_status(:success)
    end

    it 'does not gate live websites' do
      website.update!(provisioning_state: 'live')

      get '/'

      expect(response).to have_http_status(:success)
    end
  end
end
