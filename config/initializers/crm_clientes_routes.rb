# frozen_string_literal: true

# Rutas de "Clientes" (nuevo/crear) hacia SiteAdmin::ContactsController.
# Se definen aquí (append) para no interferir con edición concurrente de
# config/routes.rb. Se usa el path 'clientes/nuevo' para evitar colisión con
# la ruta show de contacts (/site_admin/contacts/:id).
Rails.application.routes.append do
  namespace :site_admin do
    get  'clientes/nuevo', to: 'contacts#new',    as: :nuevo_cliente
    post 'clientes',       to: 'contacts#create', as: :clientes
  end
end
