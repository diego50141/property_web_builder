# frozen_string_literal: true

module SiteAdmin
  module IntegrationsHelper
    # Renders an SVG icon for integration categories
    def render_category_icon(icon_name)
      case icon_name.to_s
      when 'sparkles'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z'
          )
        end
      when 'users'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z'
          )
        end
      when 'mail'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z'
          )
        end
      when 'chart-bar'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z'
          )
        end
      when 'credit-card'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z'
          )
        end
      when 'map'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7'
          )
        end
      when 'cloud'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M3 15a4 4 0 004 4h9a5 5 0 10-.1-9.999 5.002 5.002 0 10-9.78 2.096A4.001 4.001 0 003 15z'
          )
        end
      when 'message-circle'
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z'
          )
        end
      else
        # Default icon
        content_tag(:svg, class: 'w-6 h-6 text-blue-600', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
          tag.path(
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'stroke-width': '2',
            d: 'M13 10V3L4 14h7v7l9-11h-7z'
          )
        end
      end
    end

    # Spanish labels for integration categories. Pwb::WebsiteIntegration::CATEGORIES
    # is hardcoded in English upstream; we translate at the view layer (consistent
    # with the rest of the LATAM site_admin) and fall back to the English value for
    # anything not mapped here, so upstream additions never break.
    INTEGRATION_CATEGORY_ES = {
      'ai'              => { name: 'Inteligencia artificial', description: 'Generación de contenido y asistencia con IA' },
      'crm'             => { name: 'CRM', description: 'Gestión de relación con clientes' },
      'email_marketing' => { name: 'Email marketing', description: 'Campañas y automatización de correo' },
      'analytics'       => { name: 'Analítica', description: 'Analítica del sitio web y del negocio' },
      'payment'         => { name: 'Pagos', description: 'Procesamiento de pagos' },
      'maps'            => { name: 'Mapas', description: 'Servicios de mapas y geocodificación' },
      'storage'         => { name: 'Almacenamiento', description: 'Almacenamiento de archivos y medios' },
      'communication'   => { name: 'Comunicación', description: 'Mensajería y notificaciones' },
      'video'           => { name: 'Generación de video', description: 'Creación y renderizado automático de video' },
      'spp'             => { name: 'Páginas de propiedad individual', description: 'Alojamiento de páginas de propiedad vía SPP' },
      'hpg'             => { name: 'Juego de adivinar el precio', description: 'Integración del juego de estimación de precios (HPG)' }
    }.freeze

    def integration_category_name(category, info)
      INTEGRATION_CATEGORY_ES.dig(category.to_s, :name) || info[:name]
    end

    def integration_category_description(category, info)
      INTEGRATION_CATEGORY_ES.dig(category.to_s, :description) || info[:description]
    end
  end
end
