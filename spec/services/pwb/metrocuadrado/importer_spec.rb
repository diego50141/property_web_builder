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

      # La extracción de fotos está anclada al property id: el fixture solo
      # trae las imágenes de 16573-M6016483, así que de los 3 inmuebles solo
      # ese termina con fotos (y con descarga encolada).
      def asset_with_photos
        imported_assets.find_by(reference: '16573-M6016483')
      end

      describe 'listing titles' do
        it 'strips the business-type noise from the portal title' do
          described_class.new(website).import(agency_url)

          listing = Pwb::SaleListing.unscoped
                                    .where(realty_asset_id: asset_with_photos.id).first
          # og:title del fixture: "Apartamento en Venta, Balcones De La Colina, Restrepo"
          expect(listing.title_es).to eq('Apartamento, Balcones De La Colina, Restrepo')
        end

        it 'cleans the "Venta de X en ... - referencia" shape too' do
          importer = described_class.new(website)
          title = importer.send(
            :display_title,
            title: 'Venta de Casa en Condominio la pradera - Restrepo - 16573-M5446068',
            reference: '16573-M5446068'
          )

          expect(title).to eq('Casa en Condominio la pradera - Restrepo')
        end
      end

      describe 'photo sync (Fase D)' do
        it 'creates photos with external_url and enqueues their download' do
          expect do
            described_class.new(website).import(agency_url)
          end.to have_enqueued_job(Pwb::DownloadScrapedImagesJob)
            .with(kind_of(String), replace_external: false)
            .exactly(1).times

          expect(imported_assets.count).to eq(3)
          expect(asset_with_photos.prop_photos.count).to eq(2)
          expect(asset_with_photos.prop_photos.pluck(:external_url)).to all(be_present)
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
          photo = asset_with_photos.prop_photos.order(:sort_order).first
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
