# frozen_string_literal: true

require 'rails_helper'

# Plan feature gating for site admin sections.
# Websites without a subscription keep legacy (full) access.
RSpec.describe 'SiteAdmin plan feature gating', type: :request do
  before(:all) do
    Pwb::TenantSettings.delete_all
    Pwb::TenantSettings.create!(
      singleton_key: 'default',
      default_available_themes: %w[default brisbane bologna]
    )
  end

  after(:all) do
    Pwb::TenantSettings.delete_all
  end

  let!(:website) { create(:pwb_website, subdomain: 'feature-gating') }
  let!(:admin_user) { create(:pwb_user, :admin, website: website, email: 'admin@feature-gating.test') }
  let(:headers) { { 'HTTP_HOST' => 'feature-gating.test.localhost' } }

  before do
    sign_in admin_user
    allow(Pwb::Current).to receive(:website).and_return(website)
    ActsAsTenant.current_tenant = website
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'CRM (pipeline and contacts)' do
    it 'allows access when the plan includes the crm feature' do
      plan = create(:pwb_plan, features: %w[crm ai_descriptions])
      create(:pwb_subscription, :active, website: website, plan: plan)

      get site_admin_pipeline_path, headers: headers

      expect(response).to have_http_status(:success)
    end

    it 'redirects to billing when the plan lacks the crm feature' do
      plan = create(:pwb_plan, features: %w[basic_themes])
      create(:pwb_subscription, :active, website: website, plan: plan)

      get site_admin_pipeline_path, headers: headers

      expect(response).to redirect_to(site_admin_billing_path)
    end

    it 'allows access without a subscription (legacy behavior)' do
      get site_admin_contacts_path, headers: headers

      expect(response).to have_http_status(:success)
    end
  end
end
