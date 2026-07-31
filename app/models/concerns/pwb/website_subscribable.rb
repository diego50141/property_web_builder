# frozen_string_literal: true

# Website::Subscribable
#
# Manages subscription and plan-related functionality.
# Provides methods for checking subscription status, features, and limits.
#
module Pwb
  module WebsiteSubscribable
    extend ActiveSupport::Concern

    # Get the current plan (or nil if no subscription)
    #
    # @return [Pwb::Plan, nil]
    def plan
      subscription&.plan
    end

    # Check if website has an active subscription (trialing or active)
    #
    # @return [Boolean]
    def has_active_subscription?
      subscription&.in_good_standing? || false
    end

    # Check if website is in trial
    #
    # @return [Boolean]
    def in_trial?
      subscription&.trialing? || false
    end

    # Get remaining trial days
    #
    # @return [Integer, nil]
    def trial_days_remaining
      subscription&.trial_days_remaining
    end

    # Check if a feature is available on the current plan
    #
    # @param feature_key [Symbol, String] The feature to check
    # @return [Boolean]
    def has_feature?(feature_key)
      return false unless subscription
      subscription.has_feature?(feature_key)
    end

    # Check if adding a property would exceed the limit
    #
    # @return [Boolean] true if can add more properties
    def can_add_property?
      return true unless subscription # No subscription = no limits (legacy behavior)

      subscription.within_property_limit?(realty_assets.count + 1)
    end

    # Count properties currently published (visible to the public).
    # A property is published when it has a listing that is active,
    # visible and not archived (same rule as the ListedProperty view).
    #
    # @return [Integer]
    def published_properties_count
      asset_ids = realty_assets.select(:id)
      sale_ids = Pwb::SaleListing.active.where(realty_asset_id: asset_ids).distinct.pluck(:realty_asset_id)
      rental_ids = Pwb::RentalListing.active.where(realty_asset_id: asset_ids).distinct.pluck(:realty_asset_id)
      (sale_ids | rental_ids).size
    end

    # Check if one more property can be published under the current plan.
    # The plan's property_limit caps PUBLISHED properties; drafts are unlimited.
    #
    # @param realty_asset [Pwb::RealtyAsset, nil] asset being published (already-published assets don't add to the count)
    # @return [Boolean]
    def can_publish_property?(realty_asset = nil)
      return true unless subscription # No subscription = no limits (legacy behavior)
      return true if plan.nil? || plan.unlimited_properties?
      return true if realty_asset&.visible? # already published, re-publishing adds nothing

      published_properties_count < plan.property_limit
    end

    # Get remaining property slots
    #
    # @return [Integer, nil] nil means unlimited
    def remaining_properties
      subscription&.remaining_properties
    end

    # Get property limit for current plan
    #
    # @return [Integer, nil] nil means unlimited
    def property_limit
      plan&.property_limit
    end

    # Check if adding a user would exceed the limit
    #
    # @return [Boolean] true if can add more users
    def can_add_user?
      return true unless subscription # No subscription = no limits (legacy behavior)

      subscription.within_user_limit?(users.count + 1)
    end

    # Get remaining user slots
    #
    # @return [Integer, nil] nil means unlimited
    def remaining_users
      subscription&.remaining_users
    end

    # Get user limit for current plan
    #
    # @return [Integer, nil] nil means unlimited
    def user_limit
      plan&.user_limit
    end
  end
end
