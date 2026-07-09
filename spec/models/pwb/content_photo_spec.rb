# frozen_string_literal: true

# == Schema Information
#
# Table name: pwb_content_photos
# Database name: primary
#
#  id           :integer          not null, primary key
#  block_key    :string
#  description  :string
#  external_url :string
#  file_size    :integer
#  folder       :string
#  image        :string
#  sort_order   :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  content_id   :integer
#
# Indexes
#
#  index_pwb_content_photos_on_content_id  (content_id)
#
require 'rails_helper'

module Pwb
  RSpec.describe ContentPhoto, type: :model do
    let(:website) { FactoryBot.create(:pwb_website) }
    let(:content_photo) { FactoryBot.create(:pwb_content_photo) }

    # Set tenant context for specs that use factories
    around do |example|
      ActsAsTenant.with_tenant(website) do
        example.run
      end
    end

    it 'has a valid factory' do
      expect(content_photo).to be_valid
    end

    describe '#optimized_image_url' do
      it 'never raises when URL generation fails (e.g. Disk service without url_options in db:seed)' do
        photo = FactoryBot.create(:pwb_content_photo, :with_image)

        expect { photo.optimized_image_url }.not_to raise_error
      end

      it 'returns the external_url for external photos' do
        photo = FactoryBot.create(:pwb_content_photo, external_url: 'https://cdn.example.com/a.jpg')

        expect(photo.optimized_image_url).to eq('https://cdn.example.com/a.jpg')
      end
    end
  end
end
