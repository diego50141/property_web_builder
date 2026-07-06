# LATAM SaaS customizations, kept in their own file so upstream PropertyWebBuilder
# updates stay easy to merge. Idempotent: safe to run on every boot.
namespace :latam do
  desc "Configure the demo tenant for local/dev (subdomain, locale, currency)"
  task configure_demo: :environment do
    website = Pwb::Website.first
    if website.nil?
      warn "[latam] No Pwb::Website found; run db:seed first."
      next
    end

    # The dev/site_admin tenant resolver looks up the website by the 'default'
    # subdomain when there is no real subdomain (localhost / bare IP).
    website.subdomain = "default" if website.subdomain != "default"

    # LATAM defaults: Spanish UI + Colombian Peso. Locale codes are the base
    # codes PWB actually loads (I18n.available_locales => :es, :en, ...).
    website.default_client_locale = "es"
    website.default_admin_locale = "es"
    website.supported_locales = %w[es en]

    website.default_currency = "COP"
    website.available_currencies = %w[COP USD] if website.respond_to?(:available_currencies=)
    website.supported_currencies = %w[COP USD] if website.respond_to?(:supported_currencies=)

    website.save!

    puts "[latam] demo website ##{website.id} subdomain=#{website.subdomain} " \
         "locale=#{website.default_client_locale} currency=#{website.default_currency}"
  end

  desc "Create/refresh a Bogotá demo property priced in COP (idempotent)"
  task demo_cop_property: :environment do
    website = Pwb::Website.first
    if website.nil?
      warn "[latam] No Pwb::Website found; run db:seed first."
      next
    end

    ActsAsTenant.with_tenant(website) do
      reference = "COP-DEMO-1"
      asset = Pwb::RealtyAsset.find_or_initialize_by(website: website, reference: reference)
      asset.assign_attributes(
        count_bedrooms: 3, count_bathrooms: 2, count_garages: 1,
        constructed_area: 95, plot_area: 95,
        street_address: "Calle 100 # 15-20", city: "Bogotá",
        region: "Cundinamarca", country: "CO",
        latitude: 4.6866, longitude: -74.0483,
        prop_type_key: "apartment", prop_state_key: "excellent"
      )
      asset.save!

      # Visible + active sale listing priced in Colombian pesos.
      # money-rails stores cents (subunit x100): 650,000,000 COP => 65_000_000_000.
      sale = asset.sale_listings.first_or_initialize
      sale.assign_attributes(
        active: true, visible: true,
        price_sale_current_cents: 650_000_000 * 100,
        price_sale_current_currency: "COP"
      )
      sale.save!
      sale.title_es = "Apartamento moderno en el norte de Bogotá"
      sale.description_es = "Amplio apartamento de 3 habitaciones y 2 baños en el norte de Bogotá, " \
                            "con excelente ubicación, garaje y acabados de lujo."
      sale.title_en = "Modern apartment in northern Bogotá"
      sale.save!

      # Public reads may come from the ListedProperty materialized view.
      begin
        Pwb::ListedProperty.refresh if defined?(Pwb::ListedProperty) && Pwb::ListedProperty.respond_to?(:refresh)
      rescue StandardError => e
        puts "[latam] ListedProperty.refresh skipped: #{e.message}"
      end

      puts "[latam] demo COP property #{reference} -> #{sale.price_sale_current.format(no_cents: true)} " \
           "(city=#{asset.city}, visible=#{sale.visible})"
    end
  end
end
