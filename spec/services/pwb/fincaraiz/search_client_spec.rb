# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Fincaraiz
    RSpec.describe SearchClient do
      def page_html(items, current_page: 1, last_page: 1, total: nil)
        payload = {
          props: {
            pageProps: {
              fetchResult: {
                searchFast: {
                  data: items,
                  paginatorInfo: {
                    currentPage: current_page, lastPage: last_page,
                    total: total || items.size, perPage: 21
                  }
                }
              }
            }
          }
        }
        "<html><body><script id=\"__NEXT_DATA__\" type=\"application/json\" crossorigin=\"anonymous\">" \
          "#{payload.to_json}</script></body></html>"
      end

      def raw_item(id, price: 350_000_000, bedrooms: 2, bathrooms: 1)
        {
          'id' => id,
          'link' => "/apartamento-en-venta-en-chapinero-bogota/#{id}",
          'title' => "Apartamento en Venta en Chapinero, Bogotá #{id}",
          'price' => { 'amount' => price, 'currency' => { 'id' => 4 } },
          'bedrooms' => bedrooms,
          'bathrooms' => bathrooms,
          'm2' => 62,
          'locations' => {
            'city' => [{ 'name' => 'Bogotá' }],
            'location_main' => { 'name' => 'Chapinero' }
          },
          'images' => [{ 'image' => 'https://cdn2.infocasas.com.uy/repo/img/foto1.jpg' }],
          'description' => 'texto largo que no queremos persistir'
        }
      end

      describe '.build_url' do
        it 'builds the full SEO segment grammar for venta' do
          url = described_class.build_url(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota/bogota-dc',
            price_min_cents: 300_000_000_00, price_max_cents: 400_000_000_00,
            bedrooms_min: 2, bathrooms_min: 1
          )

          expect(url).to eq(
            'https://www.fincaraiz.com.co/venta/apartamentos/bogota/bogota-dc/' \
            '2-o-mas-habitaciones/1-o-mas-banos/desde-300000000/hasta-400000000'
          )
        end

        it 'uses arriendo and appends the page segment' do
          url = described_class.build_url(
            operation_type: 'arriendo', property_type_key: 'apartamento', city_slug: 'bogota/bogota-dc',
            price_min_cents: 1_000_000_00, price_max_cents: 2_000_000_00, page: 3
          )

          expect(url).to eq(
            'https://www.fincaraiz.com.co/arriendo/apartamentos/bogota/bogota-dc/' \
            'desde-1000000/hasta-2000000/pagina3'
          )
        end

        it 'clamps rooms/baths to what the portal accepts (4+/3+)' do
          url = described_class.build_url(
            operation_type: 'venta', property_type_key: 'casa', city_slug: 'cali/valle-del-cauca',
            bedrooms_min: 7, bathrooms_min: 5
          )

          expect(url).to include('/casas/')
          expect(url).to include('4-o-mas-habitaciones')
          expect(url).to include('3-o-mas-banos')
        end

        it 'omits optional segments when no filters are given' do
          url = described_class.build_url(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'pereira/risaralda'
          )

          expect(url).to eq('https://www.fincaraiz.com.co/venta/apartamentos/pereira/risaralda')
        end
      end

      describe '.city_slug_for' do
        it 'maps verified cities to their city/department pair' do
          expect(described_class.city_slug_for('Bogotá')).to eq('bogota/bogota-dc')
          expect(described_class.city_slug_for('Santa Marta')).to eq('santa-marta/magdalena')
          expect(described_class.city_slug_for('Medellín')).to eq('medellin/antioquia')
        end

        it 'returns nil for unverified cities' do
          expect(described_class.city_slug_for('Leticia')).to be_nil
        end
      end

      describe '.search_all' do
        it 'paginates with the /paginaN segment until lastPage' do
          base = 'https://www.fincaraiz.com.co/venta/apartamentos/bogota/bogota-dc'
          stub_request(:get, base)
            .to_return(status: 200, body: page_html([raw_item(1), raw_item(2)], current_page: 1, last_page: 2, total: 3))
          stub_request(:get, "#{base}/pagina2")
            .to_return(status: 200, body: page_html([raw_item(3)], current_page: 2, last_page: 2, total: 3))

          results = described_class.search_all(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota/bogota-dc'
          )

          expect(results.map { |r| r['id'] }).to eq([1, 2, 3])
        end

        it 'stops at max_results without fetching further pages' do
          base = 'https://www.fincaraiz.com.co/venta/apartamentos/bogota/bogota-dc'
          stub_request(:get, base)
            .to_return(status: 200, body: page_html([raw_item(1), raw_item(2)], current_page: 1, last_page: 99, total: 500))

          results = described_class.search_all(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota/bogota-dc',
            max_results: 2
          )

          expect(results.size).to eq(2)
          expect(a_request(:get, "#{base}/pagina2")).not_to have_been_made
        end

        it 'raises loudly when the page no longer embeds NEXT_DATA (portal change)' do
          stub_request(:get, 'https://www.fincaraiz.com.co/venta/apartamentos/bogota/bogota-dc')
            .to_return(status: 200, body: '<html><body>rediseñado</body></html>')

          expect do
            described_class.search_all(
              operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota/bogota-dc'
            )
          end.to raise_error(/NEXT_DATA/)
        end
      end

      describe '.normalize' do
        it 'maps portal fields to the normalized shape' do
          normalized = described_class.normalize(raw_item(193_967_607))

          expect(normalized).to include(
            reference: '193967607',
            source_url: 'https://www.fincaraiz.com.co/apartamento-en-venta-en-chapinero-bogota/193967607',
            price_cents: 350_000_000_00,
            bedrooms: 2,
            bathrooms: 1,
            area: 62,
            city: 'Bogotá',
            neighborhood: 'Chapinero',
            thumbnail_url: 'https://cdn2.infocasas.com.uy/repo/img/foto1.jpg'
          )
        end

        it 'drops heavy keys from raw payload' do
          normalized = described_class.normalize(raw_item(1))

          expect(normalized[:raw]).not_to have_key('description')
          expect(normalized[:raw]).not_to have_key('images')
          expect(normalized[:raw]).to have_key('price')
        end
      end
    end
  end
end
