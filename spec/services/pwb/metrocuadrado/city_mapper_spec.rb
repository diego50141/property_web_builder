# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe CityMapper do
      describe '.slug_for' do
        # Slugs verificados a mano contra /rest-search/search (ver comentario
        # en city_mapper.rb). No agregar ciudades acá sin confirmarlas primero.
        {
          'Bogotá' => 'bogota',
          'Bogotá D.C.' => 'bogota',
          'bogota' => 'bogota',
          'Medellín' => 'medellin',
          'Cali' => 'cali',
          'Cartagena' => 'cartagena',
          'Barranquilla' => 'barranquilla',
          'Bucaramanga' => 'bucaramanga',
          'Pereira' => 'pereira',
          'Santa Marta' => 'santa-marta',
          'Villavicencio' => 'villavicencio'
        }.each do |input, expected_slug|
          it "maps #{input.inspect} to #{expected_slug.inspect}" do
            expect(described_class.slug_for(input)).to eq(expected_slug)
          end
        end

        it 'returns nil for an unverified city instead of guessing a slug' do
          expect(described_class.slug_for('Leticia')).to be_nil
        end

        it 'returns nil for blank input' do
          expect(described_class.slug_for(nil)).to be_nil
          expect(described_class.slug_for('')).to be_nil
        end
      end

      describe '.known?' do
        it 'is true for a mapped city' do
          expect(described_class.known?('Bogotá')).to be(true)
        end

        it 'is false for an unmapped city' do
          expect(described_class.known?('Leticia')).to be(false)
        end
      end
    end
  end
end
