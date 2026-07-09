# frozen_string_literal: true

# == Schema Information
#
# Table name: pwb_prop_photos
# Database name: primary
#
#  id              :integer          not null, primary key
#  description     :string
#  external_url    :string
#  file_size       :integer
#  folder          :string
#  image           :string
#  sort_order      :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  prop_id         :integer
#  realty_asset_id :uuid
#
# Indexes
#
#  index_pwb_prop_photos_on_prop_id          (prop_id)
#  index_pwb_prop_photos_on_realty_asset_id  (realty_asset_id)
#
# Foreign Keys
#
#  fk_rails_...  (realty_asset_id => pwb_realty_assets.id)
#
require 'rails_helper'

module Pwb
  RSpec.describe PropPhoto, type: :model do
    let(:prop_photo) { FactoryBot.create(:pwb_prop_photo) }

    it 'has a valid factory' do
      expect(prop_photo).to be_valid
    end

    describe '#external? (attachment takes priority over external_url)' do
      it 'is external with only an external_url' do
        photo = FactoryBot.create(:pwb_prop_photo, :with_external_url)

        expect(photo).to be_external
        expect(photo.image_url).to eq(photo.external_url)
      end

      it 'is not external once the image is downloaded, keeping external_url as provenance' do
        photo = FactoryBot.create(:pwb_prop_photo, :with_external_url, :with_image)

        expect(photo).not_to be_external
        expect(photo.external_url).to be_present
        expect(photo.image_url).not_to eq(photo.external_url)
      end

      it 'is not external without any image' do
        photo = FactoryBot.create(:pwb_prop_photo)

        expect(photo).not_to be_external
        expect(photo.has_image?).to be(false)
      end
    end
  end
end
