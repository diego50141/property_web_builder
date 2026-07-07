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

  desc "Crear un sitio nuevo desde una agencia de Metrocuadrado (Fase C). " \
       "Uso: rake 'latam:provision_metrocuadrado[URL_AGENCIA,subdominio_opcional]'"
  task :provision_metrocuadrado, [:url, :subdomain] => :environment do |_t, args|
    url = args[:url].to_s.strip
    if url.empty?
      warn "Uso: rake 'latam:provision_metrocuadrado[https://www.metrocuadrado.com/inmobiliaria/<slug>/<id>,subdominio]'"
      next
    end

    result = Pwb::Metrocuadrado::AutoProvisioner.provision(
      agency_url: url,
      subdomain: args[:subdomain].to_s.strip.presence
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
    else
      warn "[metrocuadrado] auto-provisión falló: #{result.error}"
      exit 1
    end
  end
end
