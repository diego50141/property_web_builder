# frozen_string_literal: true

require 'rails_helper'

# El aprovisionamiento se encola en vez de correr dentro de la petición: el
# sembrado tarda minutos y antes dejaba la barra en 0% y el sitio a medias si
# el navegador se iba.
RSpec.describe Pwb::SignupController, type: :controller do
  let(:website) { create(:pwb_website, subdomain: 'signup-provision', provisioning_state: 'owner_assigned') }
  let(:user) { create(:pwb_user, email: 'owner@signup-provision.test', website: website) }

  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
    session[:signup_user_id] = user.id
    session[:signup_website_id] = website.id
  end

  describe 'POST #provision' do
    it 'encola el job y responde al instante sin aprovisionar en la petición' do
      expect(Pwb::ProvisioningService).not_to receive(:new)

      expect do
        post :provision, format: :json
      end.to have_enqueued_job(Pwb::ProvisionWebsiteJob).with(website.id)

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body['success']).to be(true)
      expect(body['status']).to eq('owner_assigned')
    end

    it 'no vuelve a encolar si el sitio ya viene avanzando' do
      website.update!(provisioning_state: 'field_keys_created')

      expect do
        post :provision, format: :json
      end.not_to have_enqueued_job(Pwb::ProvisionWebsiteJob)

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['status']).to eq('field_keys_created')
    end

    it 'reintenta cuando el sitio quedó en estado fallido' do
      website.update!(provisioning_state: 'failed')

      expect do
        post :provision, format: :json
      end.to have_enqueued_job(Pwb::ProvisionWebsiteJob).with(website.id)

      expect(website.reload.provisioning_state).to eq('pending')
    end

    it 'con force reinicia un sitio que quedó a medias' do
      website.update!(provisioning_state: 'field_keys_created')

      expect do
        post :provision, params: { force: 'true' }, format: :json
      end.to have_enqueued_job(Pwb::ProvisionWebsiteJob).with(website.id)

      expect(website.reload.provisioning_state).to eq('pending')
    end

    it 'responde live sin encolar cuando el sitio ya está publicado' do
      website.update!(provisioning_state: 'live')

      expect do
        post :provision, format: :json
      end.not_to have_enqueued_job(Pwb::ProvisionWebsiteJob)

      expect(JSON.parse(response.body)['status']).to eq('live')
    end
  end

  describe 'GET #status' do
    it 'marca finished y awaiting_email_verification cuando el sitio espera verificación' do
      website.update!(provisioning_state: 'locked_pending_email_verification', owner_email: 'owner@signup-provision.test')

      get :status, format: :json

      body = JSON.parse(response.body)
      expect(body['finished']).to be(true)
      expect(body['awaiting_email_verification']).to be(true)
      expect(body['owner_email']).to eq('owner@signup-provision.test')
      # El signup nunca llega a 'live' por sí solo: si el front esperara eso
      # se quedaría sondeando para siempre en 95%.
      expect(body['complete']).to be(false)
    end

    it 'marca failed cuando el aprovisionamiento falló' do
      website.update!(provisioning_state: 'failed', provisioning_error: 'algo explotó')

      get :status, format: :json

      body = JSON.parse(response.body)
      expect(body['failed']).to be(true)
      expect(body['finished']).to be(false)
    end
  end
end
