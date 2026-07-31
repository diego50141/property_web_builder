# frozen_string_literal: true

require 'rails_helper'

# Free plan: property_limit caps PUBLISHED properties (active + visible +
# not archived listings); drafts are unlimited. See ListingStateable and
# Pwb::WebsiteSubscribable#can_publish_property?.
RSpec.describe 'Publish limit enforcement' do
  let(:website) { create(:pwb_website) }
  let(:plan) { create(:pwb_plan, slug: 'test-limited', property_limit: 2, features: %w[ai_descriptions crm]) }
  let!(:subscription) { create(:pwb_subscription, :active, website: website, plan: plan) }

  def create_published_asset(website)
    asset = create(:pwb_realty_asset, website: website)
    create(:pwb_sale_listing, realty_asset: asset, active: true, visible: true, archived: false)
    asset
  end

  describe 'Pwb::Website#published_properties_count' do
    it 'counts only assets with an active, visible, non-archived listing' do
      create_published_asset(website)

      draft_asset = create(:pwb_realty_asset, website: website)
      create(:pwb_sale_listing, realty_asset: draft_asset, active: false, visible: true)

      hidden_asset = create(:pwb_realty_asset, website: website)
      create(:pwb_sale_listing, realty_asset: hidden_asset, active: true, visible: false)

      expect(website.published_properties_count).to eq(1)
    end

    it 'counts an asset once even with sale and rental listings published' do
      asset = create_published_asset(website)
      create(:pwb_rental_listing, realty_asset: asset, active: true, visible: true, archived: false)

      expect(website.published_properties_count).to eq(1)
    end
  end

  describe 'Pwb::Website#can_publish_property?' do
    it 'allows publishing while under the limit' do
      create_published_asset(website)
      expect(website.can_publish_property?).to be true
    end

    it 'blocks publishing at the limit' do
      2.times { create_published_asset(website) }
      expect(website.can_publish_property?).to be false
    end

    it 'allows re-publishing an already published asset' do
      2.times { create_published_asset(website) }
      published = website.realty_assets.first

      expect(website.can_publish_property?(published)).to be true
    end

    it 'has no limit without a subscription (legacy behavior)' do
      subscription.destroy!
      3.times { create_published_asset(website.reload) }

      expect(website.reload.can_publish_property?).to be true
    end
  end

  describe 'ListingStateable publish validation' do
    it 'blocks activating a listing beyond the limit' do
      2.times { create_published_asset(website) }
      draft = create(:pwb_realty_asset, website: website)
      listing = create(:pwb_sale_listing, realty_asset: draft, active: false, visible: true)

      expect { listing.activate! }.to raise_error(ActiveRecord::RecordInvalid, /propiedades publicadas/)
    end

    it 'blocks making a draft visible beyond the limit' do
      2.times { create_published_asset(website) }
      draft = create(:pwb_realty_asset, website: website)
      listing = create(:pwb_sale_listing, realty_asset: draft, active: true, visible: false)

      listing.visible = true
      expect(listing).not_to be_valid
      expect(listing.errors[:base].join).to include('propiedades publicadas')
    end

    it 'allows unlimited drafts' do
      2.times { create_published_asset(website) }

      draft = create(:pwb_realty_asset, website: website)
      listing = build(:pwb_sale_listing, realty_asset: draft, active: false, visible: false)

      expect(listing).to be_valid
    end

    it 'allows editing an already published listing' do
      2.times { create_published_asset(website) }
      listing = Pwb::SaleListing.active.joins(:realty_asset)
                                .where(pwb_realty_assets: { website_id: website.id }).first

      listing.price_sale_current_cents = 999_999
      expect(listing).to be_valid
    end

    it 'allows swapping the active listing of a published asset at the limit' do
      2.times { create_published_asset(website) }
      asset = website.realty_assets.first
      replacement = create(:pwb_sale_listing, realty_asset: asset, active: false, visible: true)

      expect { replacement.activate! }.not_to raise_error
    end

    it 'does not limit listings on websites without subscription' do
      subscription.destroy!
      3.times { create_published_asset(website.reload) }

      expect(website.reload.published_properties_count).to eq(3)
    end
  end

  describe 'Pwb::Subscription#remaining_properties' do
    it 'is based on published count, not total assets' do
      create_published_asset(website)
      create(:pwb_realty_asset, website: website) # draft, no listing

      expect(subscription.reload.remaining_properties).to eq(1)
    end
  end
end
