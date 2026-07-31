# frozen_string_literal: true

# == Schema Information
#
# Table name: pwb_property_requirements
# Database name: primary
#
#  id                :bigint           not null, primary key
#  bathrooms_min     :integer
#  bedrooms_min      :integer
#  city              :string
#  city_slug         :string
#  error_message     :text
#  last_searched_at  :datetime
#  operation_type    :string           default("venta"), not null
#  price_currency    :string           default("COP"), not null
#  price_max_cents   :bigint
#  price_min_cents   :bigint
#  property_type_key :string           default("apartamento"), not null
#  results_count     :integer          default(0), not null
#  status            :string           default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  contact_id        :bigint
#  created_by_id     :bigint
#  website_id        :bigint           not null
#
# Indexes
#
#  index_pwb_property_requirements_on_contact_id  (contact_id)
#  index_pwb_property_requirements_on_status      (status)
#  index_pwb_property_requirements_on_website_id  (website_id)
#
FactoryBot.define do
  factory :pwb_property_requirement, class: 'Pwb::PropertyRequirement', aliases: [:property_requirement] do
    website { Pwb::Website.first || association(:pwb_website) }
    operation_type { 'venta' }
    property_type_key { 'apartamento' }
    city { 'Bogotá' }
    city_slug { 'bogota' }
    price_min_cents { 300_000_000_00 }
    price_max_cents { 400_000_000_00 }
    bedrooms_min { 2 }
    bathrooms_min { 1 }

    trait :rent do
      operation_type { 'arriendo' }
      price_min_cents { 1_000_000_00 }
      price_max_cents { 2_000_000_00 }
    end

    trait :with_contact do
      contact { association(:pwb_contact, website: website) }
    end
  end
end
