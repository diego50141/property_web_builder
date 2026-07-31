# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Property Search', type: :request do
  let!(:website) { create(:pwb_website) }

  before do
    # Use a platform domain so SubdomainTenant can resolve the tenant from the host
    host! "#{website.subdomain}.localhost"
  end

  after do
    # Clean up tenant after each test
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET /buy' do
    it 'renders search page successfully' do
      get '/en/buy'
      expect(response).to have_http_status(:success)
    end

    it 'includes search results container' do
      get '/en/buy'
      expect(response.body).to include('search-results')
    end
  end

  describe 'GET /rent' do
    it 'renders rent search page successfully' do
      get '/en/rent'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'filtering by property type' do
    before do
      apartment = create(:pwb_realty_asset, website: website, prop_type_key: 'types.apartment')
      create(:pwb_sale_listing, realty_asset: apartment, active: true, visible: true)

      country_house = create(:pwb_realty_asset, website: website, prop_type_key: 'types.country_house')
      create(:pwb_sale_listing, realty_asset: country_house, active: true, visible: true)

      Pwb::ListedProperty.refresh(concurrently: false)
    end

    it 'filters by a single-word type slug' do
      get '/en/buy.json', params: { type: 'apartment' }
      expect(JSON.parse(response.body)['total_count']).to eq(1)
    end

    it 'filters by a multi-word (underscore) type slug' do
      get '/en/buy.json', params: { type: 'country_house' }
      expect(JSON.parse(response.body)['total_count']).to eq(1)
    end

    it 'filters by the full field key sent by the search form select' do
      get '/en/buy.json', params: { search: { property_type: 'types.apartment' } }
      expect(JSON.parse(response.body)['total_count']).to eq(1)
    end
  end

  describe 'nav search dropdown (default theme)' do
    before do
      create(:pwb_link, :top_nav, website: website, slug: 'top_nav_buy', link_path: 'buy_path', visible: true)
      create(:pwb_link, :top_nav, website: website, slug: 'top_nav_rent', link_path: 'rent_path', visible: true)
    end

    context 'when the website has property-type field keys' do
      before do
        create(:pwb_field_key, website: website, global_key: 'types.apartment', tag: 'property-types')
        create(:pwb_field_key, website: website, global_key: 'types.country_house', tag: 'property-types')
      end

      it 'renders dropdown links with type slugs for Buy and Rent' do
        get '/en/buy'
        expect(response.body).to include('pwb-nav__dropdown')
        expect(response.body).to include('?type=apartment')
        expect(response.body).to include('?type=country_house')
        expect(response.body).to include('?bedrooms=2')
      end
    end

    it 'renders the nav without dropdowns when there are no property-type field keys' do
      get '/en/buy'
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('pwb-nav__dropdown-menu')
    end
  end

  describe 'URL parameter handling' do
    it 'accepts type parameter' do
      get '/en/buy', params: { type: 'apartment' }
      expect(response).to have_http_status(:success)
    end

    it 'accepts bedrooms parameter' do
      get '/en/buy', params: { bedrooms: 2 }
      expect(response).to have_http_status(:success)
    end

    it 'accepts price range parameters' do
      get '/en/buy', params: { price_min: 100_000, price_max: 500_000 }
      expect(response).to have_http_status(:success)
    end

    it 'accepts sort parameter' do
      get '/en/buy', params: { sort: 'price-asc' }
      expect(response).to have_http_status(:success)
    end

    it 'accepts view parameter' do
      get '/en/buy', params: { view: 'list' }
      expect(response).to have_http_status(:success)
    end

    it 'accepts page parameter' do
      get '/en/buy', params: { page: 2 }
      expect(response).to have_http_status(:success)
    end

    it 'accepts multiple parameters' do
      get '/en/buy', params: {
        type: 'apartment',
        bedrooms: 2,
        price_min: 100_000,
        sort: 'price-desc'
      }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'error handling' do
    it 'handles malformed parameters gracefully' do
      get '/en/buy', params: { bedrooms: 'not-a-number' }
      expect(response).to have_http_status(:success)
    end

    it 'ignores unknown parameters' do
      get '/en/buy', params: { unknown_param: 'value' }
      expect(response).to have_http_status(:success)
    end

    it 'handles XSS attempts in parameters' do
      get '/en/buy', params: { type: '<script>alert("xss")</script>' }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('<script>alert')
    end
  end

  describe 'Turbo Frame requests' do
    it 'responds to Turbo Frame requests' do
      get '/en/buy', headers: { 'Turbo-Frame' => 'search-results' }
      expect(response).to have_http_status(:success)
    end

    it 'applies filters in Turbo Frame request' do
      get '/en/buy',
          params: { type: 'apartment' },
          headers: { 'Turbo-Frame' => 'search-results' }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'SEO' do
    it 'includes canonical URL meta tag' do
      get '/en/buy', params: { type: 'apartment' }
      expect(response.body).to include('canonical')
    end
  end
end
