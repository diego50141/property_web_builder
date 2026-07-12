# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack', type: :request do
  describe 'fail2ban/login en modo log-only' do
    # Regresión: el blocklisted_responder devolvía nil para "dejar pasar",
    # pero Rack::Attack usa lo que devuelve el responder como respuesta Rack:
    # toda IP fichada recibía un 500 (Rack::Deflater con headers nil) en vez
    # de poder loguearse. El pass-through debe hacerse en el predicado del
    # blocklist (loguear y devolver false), nunca en el responder.
    it 'no rompe la petición de una IP fichada por fail2ban' do
      # Fuerza el estado "IP baneada"; la IP no-localhost evita el safelist
      # de desarrollo/test.
      allow(Rack::Attack::Fail2Ban).to receive(:filter).and_return(true)

      post '/users/sign_in',
           params: { user: { email: 'nadie@example.com', password: 'incorrecta' } },
           env: { 'REMOTE_ADDR' => '203.0.113.10' }

      expect(response.status).to be < 500
    end
  end
end
