# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pwb::RunPropertyRequirementSearchJob, type: :job do
  let(:website) { FactoryBot.create(:pwb_website) }
  let(:requirement) { FactoryBot.create(:pwb_property_requirement, website: website) }

  it 'delegates to PropertyRequirementSearchService' do
    expect(Pwb::PropertyRequirementSearchService).to receive(:call).with(requirement)

    described_class.perform_now(requirement.id)
  end

  it 'discards (does not retry) when the requirement no longer exists' do
    requirement_id = requirement.id
    requirement.destroy

    expect { described_class.perform_now(requirement_id) }.not_to raise_error
  end
end
