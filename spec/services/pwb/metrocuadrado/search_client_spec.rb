# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe SearchClient do
      let(:api_key) { SearchClient::DEFAULT_API_KEY }

      def stub_search(query_params, body)
        stub_request(:get, 'https://www.metrocuadrado.com/rest-search/search')
          .with(query: query_params, headers: { 'x-api-key' => api_key })
          .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      # NOTA: los params de rango van como clave repetida (saleRange=a&saleRange=b),
      # que WebMock no matchea vía `query:` con arrays; esos casos se cubren
      # probando build_url directamente (función pura). Cuidado además con
      # allow_http_connections_when_no_cassette: un stub que no matchea acá
      # NO falla — la request se va al portal real.
      describe '.build_url' do
        it 'builds saleRange in pesos (not cents) for venta' do
          url = described_class.build_url(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota',
            price_min_cents: 300_000_000_00, price_max_cents: 400_000_000_00, from: 0, size: 50
          )

          expect(url).to include('saleRange=300000000&saleRange=400000000')
          expect(url).not_to include('leaseRange')
          expect(url).to include('realEstateBusinessList=venta')
        end

        it 'uses leaseRange (not saleRange) for arriendo' do
          url = described_class.build_url(
            operation_type: 'arriendo', property_type_key: 'apartamento', city_slug: 'bogota',
            price_min_cents: 1_000_000_00, price_max_cents: 2_000_000_00, from: 0, size: 50
          )

          expect(url).to include('leaseRange=1000000&leaseRange=2000000')
          expect(url).not_to include('saleRange')
          expect(url).to include('realEstateBusinessList=arriendo')
        end
      end

      describe '.search' do
        it 'parses the portal response and sends the api key' do
          stub_search(
            { 'size' => '50', 'from' => '0', 'realEstateTypeList' => 'apartamento',
              'realEstateBusinessList' => 'venta', 'city' => 'bogota' },
            { 'totalHits' => 1, 'results' => [{ 'midinmueble' => 'ABC-1' }] }
          )

          result = described_class.search(operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota')

          expect(result).to eq(total_hits: 1, results: [{ 'midinmueble' => 'ABC-1' }])
        end

        it 'raises when city_slug is missing (never silently searches nationwide)' do
          expect do
            described_class.search(operation_type: 'venta', property_type_key: 'apartamento', city_slug: nil)
          end.to raise_error(SearchClient::MissingCityError)
        end
      end

      describe '.search_all' do
        it 'paginates with from += 50 until totalHits is covered' do
          first_page = { 'totalHits' => 60, 'results' => Array.new(50) { |i| { 'midinmueble' => "P#{i}" } } }
          second_page = { 'totalHits' => 60, 'results' => Array.new(10) { |i| { 'midinmueble' => "Q#{i}" } } }

          stub_request(:get, %r{rest-search/search})
            .with(query: hash_including('from' => '0'))
            .to_return(status: 200, body: first_page.to_json)
          stub_request(:get, %r{rest-search/search})
            .with(query: hash_including('from' => '50'))
            .to_return(status: 200, body: second_page.to_json)

          results = described_class.search_all(operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota')

          expect(results.size).to eq(60)
          expect(a_request(:get, %r{rest-search/search}).with(query: hash_including('from' => '100')))
            .not_to have_been_made
        end

        it 'stops once max_results is reached without over-fetching' do
          page = { 'totalHits' => 500, 'results' => Array.new(50) { |i| { 'midinmueble' => "P#{i}" } } }
          stub_request(:get, %r{rest-search/search}).to_return(status: 200, body: page.to_json)

          results = described_class.search_all(
            operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota', max_results: 60
          )

          expect(results.size).to eq(60)
          expect(a_request(:get, %r{rest-search/search})).to have_been_made.times(2)
        end

        it 'stops when the portal returns an empty page' do
          empty_page = { 'totalHits' => 1000, 'results' => [] }
          stub_request(:get, %r{rest-search/search}).to_return(status: 200, body: empty_page.to_json)

          results = described_class.search_all(operation_type: 'venta', property_type_key: 'apartamento', city_slug: 'bogota')

          expect(results).to eq([])
        end
      end
    end
  end
end
