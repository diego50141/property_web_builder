# Importación de propiedades desde Metrocuadrado. Kept apart from upstream so
# merges stay clean.
namespace :latam do
  desc "Importar propiedades desde una URL de Metrocuadrado (agencia o inmueble). Uso: rake 'latam:import_metrocuadrado[URL]'"
  task :import_metrocuadrado, [:url] => :environment do |_t, args|
    url = args[:url].to_s.strip
    if url.empty?
      warn "Uso: rake 'latam:import_metrocuadrado[https://www.metrocuadrado.com/inmobiliaria/<slug>/<id>]'"
      next
    end

    website = Pwb::Website.first
    if website.nil?
      warn "[metrocuadrado] No hay Pwb::Website; corre db:seed primero."
      next
    end

    website.update!(external_image_mode: true) unless website.external_image_mode

    results = Pwb::Metrocuadrado::Importer.new(website).import(url)
    imported = results.count { |r| r.action == "imported" }
    errored  = results.count { |r| r.action == "error" }

    results.each do |r|
      puts "  [#{r.action}] #{r.reference} fotos=#{r.photos} #{r.error}"
    end
    puts "[metrocuadrado] #{imported} importada(s), #{errored} con error, sobre website ##{website.id}"
  end

  desc "Resincronizar los sitios provisionados desde Metrocuadrado (Fase D). " \
       "Uso: rake latam:resync_metrocuadrado  |  rake 'latam:resync_metrocuadrado[website_id]'"
  task :resync_metrocuadrado, [:website_id] => :environment do |_t, args|
    websites = Pwb::Metrocuadrado::SyncRegistry.resyncable_websites
    websites = websites.where(id: args[:website_id]) if args[:website_id].present?

    if websites.none?
      puts "[metrocuadrado] No hay sitios con resync habilitado " \
           "(imports_config.metrocuadrado.auto_resync)."
      next
    end

    websites.find_each do |website|
      Pwb::Metrocuadrado::ResyncJob.perform_now(website_id: website.id)
      last = website.reload.imports_config.dig("metrocuadrado", "last_result") || {}
      puts "[metrocuadrado] ##{website.id} #{website.subdomain}: " \
           "#{last['imported']} importadas, #{last['errors']} con error, #{last['skipped']} omitidas"
    end
  end

  desc "Crear un sitio nuevo desde una agencia de Metrocuadrado (Fase C). " \
       "Uso: rake 'latam:provision_metrocuadrado[URL_AGENCIA,subdominio_opcional,preview]' " \
       "(tercer arg 'preview' lo deja sin publicar)"
  task :provision_metrocuadrado, [:url, :subdomain, :mode] => :environment do |_t, args|
    url = args[:url].to_s.strip
    if url.empty?
      warn "Uso: rake 'latam:provision_metrocuadrado[https://www.metrocuadrado.com/inmobiliaria/<slug>/<id>,subdominio,preview]'"
      next
    end

    result = Pwb::Metrocuadrado::AutoProvisioner.provision(
      agency_url: url,
      subdomain: args[:subdomain].to_s.strip.presence,
      publish: args[:mode].to_s.strip.downcase != "preview"
    )

    if result.success?
      imported = result.import_results.count { |r| r.action == "imported" }
      errored = result.import_results.count { |r| r.action == "error" }
      result.import_results.each do |r|
        puts "  [#{r.action}] #{r.reference} fotos=#{r.photos} #{r.error}"
      end
      puts "[metrocuadrado] website ##{result.website.id} (#{result.website.subdomain}) " \
           "#{result.created ? 'creado' : 'reutilizado'}: agencia '#{result.agency_data[:name]}', " \
           "#{imported} propiedad(es) importada(s), #{errored} con error"
      if result.website.preview_pending_publish?
        puts "[metrocuadrado] EN PREVIEW (sin publicar). Navegar: " \
             "#{result.website.primary_url}/?preview_token=#{result.website.preview_token}"
      end
    else
      warn "[metrocuadrado] auto-provisión falló: #{result.error}"
      exit 1
    end
  end
end
