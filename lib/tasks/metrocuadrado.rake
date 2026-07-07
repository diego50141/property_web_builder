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
end
