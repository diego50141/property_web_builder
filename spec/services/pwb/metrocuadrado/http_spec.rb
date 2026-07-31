# frozen_string_literal: true

require 'rails_helper'

module Pwb
  module Metrocuadrado
    RSpec.describe Http do
      let(:url) { 'https://www.metrocuadrado.com/inmobiliaria/llanocasa/7157' }

      describe '.fetch' do
        it 'returns the body encoded as UTF-8' do
          stub_request(:get, url).to_return(status: 200, body: 'Bogotá')

          body = described_class.fetch(url)

          expect(body).to eq('Bogotá')
          expect(body.encoding).to eq(Encoding::UTF_8)
        end

        it 'retries transient 5xx errors and succeeds' do
          stub_request(:get, url)
            .to_return({ status: 503 }, { status: 200, body: 'ok' })

          expect(described_class.fetch(url)).to eq('ok')
          expect(a_request(:get, url)).to have_been_made.times(2)
        end

        it 'retries 429 (rate-limited) responses' do
          stub_request(:get, url)
            .to_return({ status: 429 }, { status: 200, body: 'ok' })

          expect(described_class.fetch(url)).to eq('ok')
        end

        it 'retries timeouts' do
          stub_request(:get, url).to_timeout.then
                                 .to_return(status: 200, body: 'ok')

          expect(described_class.fetch(url)).to eq('ok')
        end

        it 'gives up after MAX_ATTEMPTS and reports the attempt count' do
          stub_request(:get, url).to_return(status: 503)

          expect { described_class.fetch(url) }
            .to raise_error(/HTTP 503.*tras 3 intentos/)
          expect(a_request(:get, url)).to have_been_made.times(3)
        end

        it 'does not retry client errors like 404' do
          stub_request(:get, url).to_return(status: 404)

          expect { described_class.fetch(url) }.to raise_error(/HTTP 404/)
          expect(a_request(:get, url)).to have_been_made.once
        end

        it 'follows redirects' do
          other = 'https://www.metrocuadrado.com/inmobiliaria/llanocasa-nueva/7157'
          stub_request(:get, url).to_return(status: 301, headers: { 'Location' => other })
          stub_request(:get, other).to_return(status: 200, body: 'movido')

          expect(described_class.fetch(url)).to eq('movido')
        end

        it 'resolves relative redirect Locations against the current URL (Fincaraíz does this)' do
          stub_request(:get, url).to_return(status: 301, headers: { 'Location' => '/inmobiliaria/llanocasa-v2/7157' })
          stub_request(:get, 'https://www.metrocuadrado.com/inmobiliaria/llanocasa-v2/7157')
            .to_return(status: 200, body: 'relativo ok')

          expect(described_class.fetch(url)).to eq('relativo ok')
        end

        it 'uses a zero throttle in the test environment (no sleeps)' do
          expect(described_class.throttle_seconds).to eq(0)
        end

        it 'sends extra headers when given (ej. x-api-key)' do
          stub_request(:get, url).with(headers: { 'X-Api-Key' => 'secret' }).to_return(status: 200, body: 'ok')

          expect(described_class.fetch(url, headers: { 'x-api-key' => 'secret' })).to eq('ok')
        end
      end
    end
  end
end
