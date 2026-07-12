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

      describe 'anuncios retirados (soft-404 del portal)' do
        let(:gone_url) do
          'https://www.metrocuadrado.com/inmueble/venta-casa-restrepo-5-habitaciones-5-banos/16573-M5010348'
        end
        let(:soft_404_html) do
          '<html><head><meta property="og:title" content="Error 404 - Detalle - 16573-M5010348"/></head></html>'
        end

        it 'oculta los listings y no sobrescribe el asset' do
          described_class.new(website).import(agency_url)
          asset = imported_assets.find_by(reference: '16573-M5010348')
          expect(Pwb::SaleListing.unscoped.where(realty_asset_id: asset.id, visible: true)).to exist

          stub_request(:get, gone_url).to_return(status: 200, body: soft_404_html)
          results = described_class.new(website).import(agency_url)

          removed = results.find { |r| r.reference == '16573-M5010348' }
          expect(removed.action).to eq('removed')
          expect(Pwb::SaleListing.unscoped.where(realty_asset_id: asset.id, visible: true)).not_to exist
          expect(Pwb::SaleListing.unscoped.where(realty_asset_id: asset.id).first.title_es)
            .not_to include('Error 404')
        end
      end

      describe 'anuncios que desaparecen de la página de la agencia' do
        def create_stale_asset
          ActsAsTenant.with_tenant(website) do
            asset = Pwb::RealtyAsset.create!(website: website, reference: '16573-M9999999')
            asset.sale_listings.create!(reference: '16573-M9999999', visible: true, active: true,
                                        price_sale_current_cents: 100_00, price_sale_current_currency: 'COP')
            asset
          end
        end

        it 'hides listings for assets no longer listed by the agency' do
          stale = create_stale_asset

          results = described_class.new(website).import(agency_url)

          removed = results.find { |r| r.reference == '16573-M9999999' }
          expect(removed.action).to eq('removed')
          expect(Pwb::SaleListing.unscoped.where(realty_asset_id: stale.id, visible: true)).not_to exist
        end

        it 'does not hide anything when a property fetch failed mid-crawl' do
          stale = create_stale_asset
          stub_request(:get, %r{/inmueble/venta-casa-restrepo}).to_return(status: 404)

          described_class.new(website).import(agency_url)

          expect(Pwb::SaleListing.unscoped.where(realty_asset_id: stale.id, visible: true)).to exist
        end
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

          described_class.new(website).import(agency_url)

          ids_after = imported_assets.flat_map { |a| a.prop_photos.order(:sort_order).pluck(:id) }
          expect(ids_after).to eq(ids_before)
        end

        # Si la descarga original se perdió (p. ej. proceso rake que terminó
        # con la cola :async sin drenar), el resync debe re-dispararla aunque
        # las URLs del portal no hayan cambiado.
        it 're-enqueues the download when unchanged photos still lack attachments' do
          described_class.new(website).import(agency_url)

          expect do
            described_class.new(website).import(agency_url)
          end.to have_enqueued_job(Pwb::DownloadScrapedImagesJob)
            .with(asset_with_photos.id, replace_external: false)
        end

        it 'does not re-enqueue when every photo already has its attachment' do
          described_class.new(website).import(agency_url)
          asset_with_photos.prop_photos.each do |photo|
            photo.image.attach(io: StringIO.new('img'), filename: 'a.jpg', content_type: 'image/jpeg')
          end

          expect do
            described_class.new(website).import(agency_url)
          end.not_to have_enqueued_job(Pwb::DownloadScrapedImagesJob)
        end

        it 'descarga las fotos en el mismo proceso con inline_images (rake/CLI)' do
          stub_request(:get, %r{\Ahttps://multimedia\.metrocuadrado\.com/})
            .to_return(status: 200, body: 'imgdata', headers: { 'Content-Type' => 'image/jpeg' })

          expect do
            described_class.new(website, inline_images: true).import(agency_url)
          end.not_to have_enqueued_job(Pwb::DownloadScrapedImagesJob)

          expect(asset_with_photos.prop_photos.reload).to all(satisfy { |p| p.image.attached? })
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
