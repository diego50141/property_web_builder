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

  # Upstream demo seeds ship US/EU sample properties. For a LATAM client demo we
  # only want local (Colombian) listings on the public site, so this unpublishes
  # every listing whose property is not in Colombia. Idempotent and reversible
  # (run latam:show_all_demo_props to re-publish everything).
  COLOMBIA_COUNTRY_VALUES = ["co", "col", "colombia"].freeze

  def latam_colombian_asset?(asset)
    COLOMBIA_COUNTRY_VALUES.include?(asset.country.to_s.strip.downcase)
  end

  def latam_set_listing_visibility(website, visible:, only_foreign:)
    changed = 0
    ActsAsTenant.with_tenant(website) do
      Pwb::RealtyAsset.where(website: website).find_each do |asset|
        next if only_foreign && latam_colombian_asset?(asset)

        listing_sets = [:sale_listings, :rental_listings, :spp_listings].filter_map do |assoc|
          asset.public_send(assoc) if asset.respond_to?(assoc)
        end
        listing_sets.flatten.each do |listing|
          attrs = {}
          attrs[:visible] = visible if listing.respond_to?(:visible)
          attrs[:active] = visible if listing.respond_to?(:active)
          listing.update_columns(attrs) if attrs.any?
        end
        changed += 1
      end

      begin
        Pwb::ListedProperty.refresh if defined?(Pwb::ListedProperty) && Pwb::ListedProperty.respond_to?(:refresh)
      rescue StandardError => e
        puts "[latam] ListedProperty.refresh skipped: #{e.message}"
      end
    end
    changed
  end

  desc "Unpublish non-Colombian demo properties so the demo shows only local listings (idempotent)"
  task hide_foreign_demo_props: :environment do
    website = Pwb::Website.first
    if website.nil?
      warn "[latam] No Pwb::Website found; run db:seed first."
      next
    end

    n = latam_set_listing_visibility(website, visible: false, only_foreign: true)
    puts "[latam] unpublished listings for #{n} non-Colombian demo properties"
  end

  desc "Re-publish ALL demo properties (undo hide_foreign_demo_props)"
  task show_all_demo_props: :environment do
    website = Pwb::Website.first
    if website.nil?
      warn "[latam] No Pwb::Website found; run db:seed first."
      next
    end

    n = latam_set_listing_visibility(website, visible: true, only_foreign: false)
    puts "[latam] re-published listings for #{n} demo properties"
  end
end
