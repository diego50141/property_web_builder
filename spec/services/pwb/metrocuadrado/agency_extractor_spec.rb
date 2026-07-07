# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe AgencyExtractor do
      let(:fixture_path) { Rails.root.join('spec', 'fixtures', 'metrocuadrado') }
      let(:agency_html) { File.read(fixture_path.join('agency_page.html')) }
      let(:property_html) { File.read(fixture_path.join('property_page.html')) }

      describe '#call' do
        subject(:data) { described_class.new(agency_html, property_html).call }

        it 'extracts the agency identity from the property page company block' do
          expect(data[:name]).to eq('LLANOCASA')
          expect(data[:slug]).to eq('llanocasa')
          expect(data[:company_id]).to eq('7157')
        end

        it 'extracts logo, phones and address' do
          expect(data[:logo_url]).to eq('https://www.metrocuadrado.com/files/logos/company/7157/company7157.png')
          expect(data[:phone]).to eq('3017891932')
          expect(data[:whatsapp]).to eq('573017891932')
          expect(data[:street_address]).to eq('Cra 44A # 12A - 12')
        end

        it 'picks the most frequent listing city as the agency city' do
          # 2x Villavicencio, 1x Restrepo in the agency page fixture
          expect(data[:city]).to eq('Villavicencio')
        end

        it 'extracts the unique property paths' do
          expect(data[:property_paths].length).to eq(3)
          expect(data[:property_paths]).to all(match(%r{\A/inmueble/.+/\d+-M\d+\z}))
        end

        context 'without a property page' do
          subject(:data) { described_class.new(agency_html).call }

          it 'falls back to the agency page h1 for the name' do
            expect(data[:name]).to eq('LLANOCASA')
          end

          it 'still extracts city and property paths' do
            expect(data[:city]).to eq('Villavicencio')
            expect(data[:property_paths].length).to eq(3)
          end

          it 'leaves company-block fields nil' do
            expect(data[:slug]).to be_nil
            expect(data[:logo_url]).to be_nil
            expect(data[:phone]).to be_nil
          end
        end

        context 'with a non-https logo value' do
          let(:property_html) do
            File.read(fixture_path.join('property_page.html'))
                .sub('https://www.metrocuadrado.com/files/logos/company/7157/company7157.png', 'null')
          end

          it 'returns nil for the logo' do
            expect(data[:logo_url]).to be_nil
          end
        end
      end
    end
  end
end
