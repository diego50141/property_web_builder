# frozen_string_literal: true

# ListingStateable
#
# Provides common state management behavior for listing models (SaleListing, RentalListing).
# Handles activation, deactivation, archiving, and related validations.
#
# Usage:
#   class SaleListing < ApplicationRecord
#     include ListingStateable
#
#     def listings_of_same_type
#       realty_asset.sale_listings
#     end
#   end
#
# Required:
#   - Model must have: active, visible, archived boolean columns
#   - Model must belong_to :realty_asset
#   - Model must implement #listings_of_same_type returning the association
#
module ListingStateable
  extend ActiveSupport::Concern

  included do
    # Validations
    validate :only_one_active_per_realty_asset, if: :active?
    validate :cannot_delete_active_listing, on: :destroy
    validate :within_publish_limit, if: :becoming_published?

    # Scopes
    scope :visible, -> { where(visible: true) }
    scope :highlighted, -> { where(highlighted: true) }
    scope :archived, -> { where(archived: true) }
    scope :not_archived, -> { where(archived: false) }
    scope :active_listing, -> { where(active: true) }
    # Legacy scope - now refers to the active listing that is visible
    scope :active, -> { where(active: true, visible: true, archived: false) }

    # Refresh the materialized view after changes
    after_commit :refresh_properties_view

    # Callbacks for managing active state
    before_save :deactivate_other_listings, if: :will_activate?
    after_save :ensure_active_listing_visible, if: :saved_change_to_active?
  end

  # Activate this listing, deactivating any other active listing for same asset
  def activate!
    transaction do
      listings_of_same_type.where.not(id: id).update_all(active: false)
      update!(active: true, archived: false)
    end
  end

  # Deactivate this listing
  def deactivate!
    update!(active: false)
  end

  # Archive this listing (cannot archive if active, must deactivate first)
  def archive!
    raise ActiveRecord::RecordInvalid.new(self), "Cannot archive the active listing" if active?

    update!(archived: true, visible: false)
  end

  # Unarchive this listing
  def unarchive!
    update!(archived: false)
  end

  # Check if this listing can be deleted
  def can_destroy?
    !active?
  end

  private

  # Must be implemented by including class
  # @return [ActiveRecord::Relation] The association of listings of the same type
  def listings_of_same_type
    raise NotImplementedError, "#{self.class} must implement #listings_of_same_type"
  end

  def only_one_active_per_realty_asset
    if realty_asset && listings_of_same_type.active_listing.where.not(id: id).exists?
      errors.add(:active, "listing already exists for this property. Deactivate the current active listing first.")
    end
  end

  def cannot_delete_active_listing
    if active?
      errors.add(:base, "Cannot delete the active listing. Deactivate it first or activate another listing.")
      throw :abort
    end
  end

  def will_activate?
    active? && active_changed?
  end

  # A listing is "published" when it is active, visible and not archived
  # (same rule as the ListedProperty materialized view).
  def published_state?
    active? && visible? && !archived?
  end

  # Only run the limit check when this save transitions the listing INTO
  # the published state, so already-published listings can keep being edited.
  def becoming_published?
    published_state? && (new_record? || active_changed? || visible_changed? || archived_changed?)
  end

  def within_publish_limit
    website = realty_asset&.website
    return unless website.respond_to?(:can_publish_property?)
    return if website.can_publish_property?(realty_asset)

    errors.add(:base, I18n.t(
      'pwb.listings.publish_limit_reached',
      limit: website.property_limit,
      default: "Has alcanzado el límite de %{limit} propiedades publicadas de tu plan. Despublica otra propiedad o mejora tu plan."
    ))
  end

  def deactivate_other_listings
    listings_of_same_type.where.not(id: id).update_all(active: false)
  end

  def ensure_active_listing_visible
    # If marking as active, ensure it's not archived
    if active? && archived?
      update_column(:archived, false)
    end
  end

  def refresh_properties_view
    connection = ActiveRecord::Base.connection
    concurrently = connection.respond_to?(:open_transactions) ? connection.open_transactions.zero? : true
    Pwb::ListedProperty.refresh(concurrently: concurrently)
  rescue StandardError => e
    Rails.logger.warn "Failed to refresh properties view: #{e.message}"
  end
end
