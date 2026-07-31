# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'seeds', 'plans_seeds')

RSpec.describe 'Free plan assignment' do
  describe 'Pwb::PlansSeeder gratis plan' do
    before do
      allow($stdout).to receive(:puts) # silence seeder output
      Pwb::PlansSeeder.seed!
    end

    let(:plan) { Pwb::Plan.find_by(slug: 'gratis') }

    it 'seeds the free plan with the expected limits and features' do
      expect(plan).to be_present
      expect(plan.price_cents).to eq(0)
      expect(plan).to be_free
      expect(plan.property_limit).to eq(10)
      expect(plan.has_feature?(:ai_descriptions)).to be true
      expect(plan.has_feature?(:crm)).to be true
      expect(plan.has_trial?).to be false
    end

    it 'is returned by Plan.free_plan' do
      expect(Pwb::Plan.free_plan).to eq(plan)
    end
  end

  describe 'Pwb::SubscriptionService#create_free' do
    let(:service) { Pwb::SubscriptionService.new }
    let(:website) { create(:pwb_website) }
    let!(:free_plan) do
      create(:pwb_plan, name: 'gratis', slug: 'gratis', display_name: 'Gratis',
                        price_cents: 0, property_limit: 10, trial_days: 0, trial_value: 0,
                        features: %w[ai_descriptions crm])
    end

    it 'creates an active subscription on the free plan' do
      result = service.create_free(website: website)

      expect(result[:success]).to be true
      subscription = result[:subscription]
      expect(subscription.status).to eq('active')
      expect(subscription.plan).to eq(free_plan)
      expect(subscription.trial_ends_at).to be_nil
      expect(subscription.events.pluck(:event_type)).to include('free_plan_assigned')
    end

    it 'keeps an existing subscription that still allows access' do
      existing = create(:pwb_subscription, :active, website: website)

      result = service.create_free(website: website)

      expect(result[:success]).to be true
      expect(result[:subscription]).to eq(existing)
      expect(website.reload.subscription).to eq(existing)
    end

    it 'fails gracefully when the free plan is missing' do
      free_plan.destroy!

      result = service.create_free(website: website)

      expect(result[:success]).to be false
      expect(result[:errors].join).to include('Free plan not found')
    end
  end

  describe 'Pwb::ProvisioningService#assign_free_subscription' do
    let(:service) { Pwb::ProvisioningService.new }
    let(:website) { create(:pwb_website) }

    it 'assigns the free plan to a website without subscription' do
      create(:pwb_plan, name: 'gratis', slug: 'gratis', display_name: 'Gratis',
                        price_cents: 0, property_limit: 10, features: %w[ai_descriptions crm])

      service.send(:assign_free_subscription, website)

      expect(website.reload.subscription).to be_present
      expect(website.subscription.plan.slug).to eq('gratis')
      expect(website.subscription.status).to eq('active')
    end

    it 'does not replace an existing valid subscription' do
      existing = create(:pwb_subscription, :active, website: website)

      service.send(:assign_free_subscription, website)

      expect(website.reload.subscription).to eq(existing)
    end

    it 'does not raise when no free plan exists' do
      expect { service.send(:assign_free_subscription, website) }.not_to raise_error
      expect(website.reload.subscription).to be_nil
    end
  end

  describe 'Pwb::ProvisioningService#apply_latam_defaults' do
    let(:service) { Pwb::ProvisioningService.new }

    # El signup no ofrece elegir idioma/moneda: los defaults de plataforma
    # (en-UK/EUR) se sobreescriben siempre con es/COP.
    it 'forces LATAM defaults over platform defaults' do
      website = create(:pwb_website, default_client_locale: 'en-UK',
                                     supported_locales: %w[en-UK], default_currency: 'EUR')

      service.send(:apply_latam_defaults, website)

      website.reload
      expect(website.default_client_locale).to eq('es')
      expect(website.supported_locales).to eq(['es'])
      expect(website.default_currency).to eq('COP')
      expect(website.available_currencies).to eq(['COP'])
      expect(website.supported_currencies).to eq(['COP'])
    end
  end
end
