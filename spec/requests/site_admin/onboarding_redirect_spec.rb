# frozen_string_literal: true

require 'rails_helper'

# Users coming from signup (onboarding_step 1..4, wizard not completed) are
# redirected from the admin landing pages to the onboarding wizard.
# Legacy users (onboarding_step 0) are never redirected.
RSpec.describe 'SiteAdmin onboarding redirect', type: :request do
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

  let!(:website) { create(:pwb_website, subdomain: 'onboarding-redirect') }
  let(:headers) { { 'HTTP_HOST' => 'onboarding-redirect.test.localhost' } }

  before do
    sign_in admin_user
    allow(Pwb::Current).to receive(:website).and_return(website)
    ActsAsTenant.current_tenant = website
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  context 'with a user coming from signup (onboarding pending)' do
    let!(:admin_user) do
      create(:pwb_user, :admin, website: website,
                                email: 'new@onboarding-redirect.test',
                                onboarding_step: 4,
                                site_admin_onboarding_completed_at: nil)
    end

    it 'redirects the dashboard to the onboarding wizard' do
      get site_admin_root_path, headers: headers

      expect(response).to redirect_to(site_admin_onboarding_path(step: 1))
    end

    it 'redirects the properties list to the onboarding wizard' do
      get site_admin_props_path, headers: headers

      expect(response).to redirect_to(site_admin_onboarding_path(step: 1))
    end

    it 'does not redirect once onboarding is completed' do
      admin_user.update!(site_admin_onboarding_completed_at: Time.current)

      get site_admin_props_path, headers: headers

      expect(response).to have_http_status(:success)
    end
  end

  context 'with a legacy user (onboarding_step 0)' do
    let!(:admin_user) do
      create(:pwb_user, :admin, website: website,
                                email: 'legacy@onboarding-redirect.test',
                                onboarding_step: 0,
                                site_admin_onboarding_completed_at: nil)
    end

    it 'does not redirect the dashboard' do
      get site_admin_root_path, headers: headers

      expect(response).not_to redirect_to(site_admin_onboarding_path(step: 1))
    end
  end
end
