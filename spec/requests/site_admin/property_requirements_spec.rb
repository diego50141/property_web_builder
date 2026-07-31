# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SiteAdmin::PropertyRequirementsController', type: :request do
  let!(:website) { create(:pwb_website, subdomain: 'busquedas-test') }
  let!(:agency) { create(:pwb_agency, website: website) }
  let!(:admin_user) { create(:pwb_user, :admin, website: website, email: 'admin@busquedas-test.test') }
  let(:headers) { { 'HTTP_HOST' => 'busquedas-test.test.localhost' } }

  before do
    sign_in admin_user
    allow(Pwb::Current).to receive(:website).and_return(website)
  end

  def create_requirement(attrs = {})
    FactoryBot.create(:pwb_property_requirement, { website: website }.merge(attrs))
  end

  describe 'GET index' do
    it 'lists the website requirements' do
      create_requirement

      get site_admin_property_requirements_path, headers: headers

      expect(response).to have_http_status(:success)
    end

    it 'does not list requirements from other websites' do
      other_website = create(:pwb_website, subdomain: 'otra-agencia')
      foreign = FactoryBot.create(:pwb_property_requirement, website: other_website, city: 'Medellín')

      get site_admin_property_requirements_path, headers: headers

      expect(response.body).not_to include("property_requirements/#{foreign.id}\"")
    end
  end

  describe 'GET new' do
    it 'renders the form' do
      get new_site_admin_property_requirement_path, headers: headers

      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST create' do
    let(:valid_params) do
      {
        property_requirement: {
          operation_type: 'venta',
          property_type_key: 'apartamento',
          city: 'Bogotá',
          price_min: '300.000.000',
          price_max: '400000000',
          bedrooms_min: '2',
          bathrooms_min: '1'
        }
      }
    end

    it 'creates the requirement, converts pesos to cents and enqueues the search' do
      expect do
        post site_admin_property_requirements_path, params: valid_params, headers: headers
      end.to change(Pwb::PropertyRequirement, :count).by(1)
         .and have_enqueued_job(Pwb::RunPropertyRequirementSearchJob)

      requirement = Pwb::PropertyRequirement.last
      expect(requirement.website_id).to eq(website.id)
      expect(requirement.created_by_id).to eq(admin_user.id)
      expect(requirement.city_slug).to eq('bogota')
      expect(requirement.price_min_cents).to eq(300_000_000_00)
      expect(requirement.price_max_cents).to eq(400_000_000_00)
      expect(response).to redirect_to(site_admin_property_requirement_path(requirement))
    end

    it 're-renders the form when validation fails' do
      invalid = { property_requirement: valid_params[:property_requirement].merge(city: '') }

      expect do
        post site_admin_property_requirements_path, params: invalid, headers: headers
      end.not_to change(Pwb::PropertyRequirement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET show' do
    it 'renders the requirement with its matches' do
      requirement = create_requirement(status: 'completed', results_count: 1)
      requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1',
                                  title: 'Apartamento en Chapinero', price_cents: 350_000_000_00,
                                  bedrooms: 2, bathrooms: 1, source_url: '/inmueble/foo/ABC-1')

      get site_admin_property_requirement_path(requirement), headers: headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Apartamento en Chapinero')
    end

    it 'is not found for a requirement of another website' do
      other_website = create(:pwb_website, subdomain: 'otra-agencia')
      foreign = FactoryBot.create(:pwb_property_requirement, website: other_website)

      get site_admin_property_requirement_path(foreign), headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST rerun' do
    it 'resets the status and enqueues the search again' do
      requirement = create_requirement(status: 'completed', results_count: 3)

      expect do
        post rerun_site_admin_property_requirement_path(requirement), headers: headers
      end.to have_enqueued_job(Pwb::RunPropertyRequirementSearchJob).with(requirement.id)

      expect(requirement.reload.status).to eq('pending')
    end
  end

  describe 'DELETE destroy' do
    it 'removes the requirement and its matches' do
      requirement = create_requirement
      requirement.matches.create!(portal: 'metrocuadrado', external_reference: 'ABC-1')

      expect do
        delete site_admin_property_requirement_path(requirement), headers: headers
      end.to change(Pwb::PropertyRequirement, :count).by(-1)
         .and change(Pwb::PropertyRequirementMatch, :count).by(-1)
    end
  end

  describe 'plan feature gating' do
    it 'redirects to billing when the plan lacks the crm feature' do
      plan = create(:pwb_plan, features: %w[basic_themes])
      create(:pwb_subscription, :active, website: website, plan: plan)

      get site_admin_property_requirements_path, headers: headers

      expect(response).to redirect_to(site_admin_billing_path)
    end
  end
end
