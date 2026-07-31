# frozen_string_literal: true

require 'rails_helper'

module Pwb
  RSpec.describe PropertyRequirementSearchService do
    let(:website) { FactoryBot.create(:pwb_website) }
    let(:requirement) do
      FactoryBot.create(:pwb_property_requirement, website: website, bedrooms_min: 2, bathrooms_min: 1)
    end

    def m2_result(reference, rooms:, baths:, price: 350_000_000)
      {
        'midinmueble' => reference,
        'link' => "/inmueble/foo/#{reference}",
        'title' => "Apartamento #{reference}",
        'mvalorventa' => price,
        'mvalorarriendo' => nil,
        'mnrocuartos' => rooms.to_s,
        'mnrobanos' => baths.to_s,
        'areaPrivada' => 55.5,
        'mciudad' => { 'nombre' => 'Bogotá D.C.' },
        'mnombrecomunbarrio' => 'Chapinero',
        'imageLink' => 'https://multimedia.metrocuadrado.com/foo.jpg'
      }
    end

    def fr_result(id, rooms: 2, baths: 1, price: 350_000_000)
      {
        'id' => id,
        'link' => "/apartamento-en-venta/#{id}",
        'title' => "Apartamento FR #{id}",
        'price' => { 'amount' => price },
        'bedrooms' => rooms,
        'bathrooms' => baths,
        'm2' => 60,
        'locations' => { 'city' => [{ 'name' => 'Bogotá' }], 'location_main' => { 'name' => 'Cedritos' } },
        'images' => [{ 'image' => 'https://cdn2.infocasas.com.uy/x.jpg' }]
      }
    end

    def stub_portals(metrocuadrado: [], fincaraiz: [])
      allow(Metrocuadrado::SearchClient).to receive(:search_all).and_return(metrocuadrado)
      allow(Fincaraiz::SearchClient).to receive(:search_all).and_return(fincaraiz)
    end

    describe '#call' do
      it 'merges matches from both portals under their portal key' do
        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1)],
                     fincaraiz: [fr_result(77)])

        described_class.call(requirement)

        requirement.reload
        expect(requirement.status).to eq('completed')
        expect(requirement.results_count).to eq(2)
        expect(requirement.matches.pluck(:portal, :external_reference))
          .to contain_exactly(%w[metrocuadrado OK-1], %w[fincaraiz 77])
      end

      it 'filters below-minimum results from any portal' do
        stub_portals(metrocuadrado: [m2_result('LOW', rooms: 1, baths: 1)],
                     fincaraiz: [fr_result(88, rooms: 3, baths: 0)])

        described_class.call(requirement)

        expect(requirement.reload.results_count).to eq(0)
        expect(requirement.matches).to be_empty
      end

      it 'stores the parsed fields on the match' do
        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1, price: 350_000_000)])

        described_class.call(requirement)

        match = requirement.matches.find_by!(portal: 'metrocuadrado', external_reference: 'OK-1')
        expect(match.price_cents).to eq(350_000_000_00)
        expect(match.bedrooms).to eq(2)
        expect(match.bathrooms).to eq(1)
        expect(match.city).to eq('Bogotá D.C.')
        expect(match.neighborhood).to eq('Chapinero')
        expect(match.source_url).to eq('/inmueble/foo/OK-1')
      end

      it 'is idempotent per portal: re-running upserts instead of duplicating' do
        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1, price: 300_000_000)])
        described_class.call(requirement)

        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1, price: 320_000_000)])
        described_class.call(requirement)

        expect(requirement.matches.where(external_reference: 'OK-1').count).to eq(1)
        expect(requirement.matches.find_by!(external_reference: 'OK-1').price_cents).to eq(320_000_000_00)
      end

      it 'prunes stale matches only within the synced portal' do
        stub_portals(metrocuadrado: [m2_result('GONE', rooms: 2, baths: 1)], fincaraiz: [fr_result(77)])
        described_class.call(requirement)

        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1)], fincaraiz: [fr_result(77)])
        described_class.call(requirement)

        references = requirement.matches.pluck(:portal, :external_reference)
        expect(references).to contain_exactly(%w[metrocuadrado OK-1], %w[fincaraiz 77])
      end

      it 'does not prune a portal that failed this run' do
        stub_portals(metrocuadrado: [m2_result('OK-1', rooms: 2, baths: 1)], fincaraiz: [fr_result(77)])
        described_class.call(requirement)

        allow(Metrocuadrado::SearchClient).to receive(:search_all).and_return([m2_result('OK-1', rooms: 2, baths: 1)])
        allow(Fincaraiz::SearchClient).to receive(:search_all).and_raise(StandardError, 'portal caído')
        described_class.call(requirement)

        requirement.reload
        expect(requirement.status).to eq('completed')
        expect(requirement.matches.where(portal: 'fincaraiz', external_reference: '77')).to exist
        expect(requirement.error_message).to include('fincaraiz')
      end

      it 'fails gracefully when the city is not supported by any portal, without calling them' do
        requirement.update!(city: 'Leticia', city_slug: nil)
        expect(Metrocuadrado::SearchClient).not_to receive(:search_all)
        expect(Fincaraiz::SearchClient).not_to receive(:search_all)

        described_class.call(requirement)

        requirement.reload
        expect(requirement.status).to eq('failed')
        expect(requirement.error_message).to include('Leticia')
      end

      it 'marks the requirement failed only when every portal raises' do
        allow(Metrocuadrado::SearchClient).to receive(:search_all).and_raise(StandardError, 'caído m2')
        allow(Fincaraiz::SearchClient).to receive(:search_all).and_raise(StandardError, 'caído fr')

        described_class.call(requirement)

        requirement.reload
        expect(requirement.status).to eq('failed')
        expect(requirement.error_message).to include('caído m2').and include('caído fr')
      end

      it 'uses mvalorarriendo (not mvalorventa) for rental requirements' do
        rent_requirement = FactoryBot.create(:pwb_property_requirement, :rent, website: website)
        allow(Metrocuadrado::SearchClient).to receive(:search_all).and_return([
                                                                                 {
                                                                                   'midinmueble' => 'R-1',
                                                                                   'mvalorventa' => nil,
                                                                                   'mvalorarriendo' => 1_500_000,
                                                                                   'mnrocuartos' => '2',
                                                                                   'mnrobanos' => '1'
                                                                                 }
                                                                               ])
        allow(Fincaraiz::SearchClient).to receive(:search_all).and_return([])

        described_class.call(rent_requirement)

        expect(rent_requirement.matches.find_by!(external_reference: 'R-1').price_cents).to eq(1_500_000_00)
      end
    end
  end
end
