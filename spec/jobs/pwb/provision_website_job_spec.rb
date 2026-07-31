# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pwb::ProvisionWebsiteJob, type: :job do
  let(:website) { create(:pwb_website, subdomain: 'job-provision', provisioning_state: 'owner_assigned') }

  it 'delega el aprovisionamiento al servicio' do
    service = instance_double(Pwb::ProvisioningService)
    expect(Pwb::ProvisioningService).to receive(:new).and_return(service)
    expect(service).to receive(:provision_website).with(website: website)

    described_class.perform_now(website.id)
  end

  it 'no reprovisiona un sitio ya publicado' do
    website.update!(provisioning_state: 'live')
    expect(Pwb::ProvisioningService).not_to receive(:new)

    described_class.perform_now(website.id)
  end

  it 'no reprovisiona un sitio que ya terminó y espera verificación de correo' do
    website.update!(provisioning_state: 'locked_pending_email_verification')
    expect(Pwb::ProvisioningService).not_to receive(:new)

    described_class.perform_now(website.id)
  end

  it 'descarta el job si el sitio fue borrado' do
    id = website.id
    Pwb::FieldKey.where(pwb_website_id: id).delete_all
    website.destroy

    expect { described_class.perform_now(id) }.not_to raise_error
  end
end
