# frozen_string_literal: true

# Sets the admin UI language for the site_admin panel. Upstream PWB does not
# localize the admin area (it always renders in the default locale), so we pick
# the locale from the current website's `default_admin_locale` (falling back to
# the logged-in user's preference, then the app default). Kept as an isolated
# concern so upstream updates stay easy to merge.
module LatamAdminLocale
  extend ActiveSupport::Concern

  included do
    around_action :use_admin_locale
  end

  private

  def use_admin_locale(&block)
    I18n.with_locale(admin_locale, &block)
  end

  def admin_locale
    raw = nil
    raw ||= current_user.default_admin_locale if current_user.respond_to?(:default_admin_locale) && current_user&.default_admin_locale.present?
    raw ||= Pwb::Current.website&.default_admin_locale
    raw ||= I18n.default_locale.to_s

    # Normalize things like "en-UK" / "es-MX" to a base locale we actually load.
    base = raw.to_s[0, 2].to_sym
    I18n.available_locales.include?(base) ? base : I18n.default_locale
  end
end
