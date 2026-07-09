# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe Importer do
      let(:fixture_path) { Rails.root.join('spec', 'fixtures', 'metrocuadrado') }
      let(:agency_html) { File.read(fixture_path.join('agency_page.html')) }
      let(:property_html) { File.read(fixture_path.join('property_page.html')) }
      let(:agency_url) { 'https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157' }
      let(:website) { FactoryBot.create(:pwb_website) }

      before do
        stub_request(:get, agency_url).to_return(status: 200, body: agency_html)
        stub_request(:get, %r{\Ahttps://www\.metrocuadrado\.com/inmueble/})
          .to_return(status: 200, body: property_html)
      end

      def imported_assets
        Pwb::RealtyAsset.unscoped.where(website_id: website.id)
      end

      describe 'photo sync (Fase D)' do
        it 'creates photos with external_url and enqueues their download' do
          expect do
            described_class.new(website).import(agency_url)
          end.to have_enqueued_job(Pwb::DownloadScrapedImagesJob)
            .with(kind_of(String), replace_external: false)
            .exactly(3).times

          expect(imported_assets.count).to eq(3)
          asset = imported_assets.first
          expect(asset.prop_photos.count).to eq(2)
          expect(asset.prop_photos.pluck(:external_url)).to all(be_present)
        end

        it 'keeps the same photo records when re-importing unchanged listings' do
          described_class.new(website).import(agency_url)
          ids_before = imported_assets.flat_map { |a| a.prop_photos.order(:sort_order).pluck(:id) }

          expect do
            described_class.new(website).import(agency_url)
          end.not_to have_enqueued_job(Pwb::DownloadScrapedImagesJob)

          ids_after = imported_assets.flat_map { |a| a.prop_photos.order(:sort_order).pluck(:id) }
          expect(ids_after).to eq(ids_before)
        end

        it 'preserves downloaded attachments across resyncs' do
          described_class.new(website).import(agency_url)
          photo = imported_assets.first.prop_photos.order(:sort_order).first
          photo.image.attach(io: StringIO.new('img'), filename: 'a.jpg', content_type: 'image/jpeg')

          described_class.new(website).import(agency_url)

          photo.reload
          expect(photo.image).to be_attached
          expect(photo.external_url).to be_present
          expect(photo).not_to be_external
        end
      end
    end
  end
end
