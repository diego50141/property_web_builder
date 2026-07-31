# frozen_string_literal: true

module Pwb
  # Requerimiento de búsqueda de un cliente (ej. "apartamento en venta en
  # Bogotá, 300-400M, 2 habitaciones, 1 baño") contra portales externos.
  #
  # No genera Pwb::RealtyAsset: las opciones encontradas (PropertyRequirementMatch)
  # son inventario de terceros, no propio. `operation_type` y `property_type_key`
  # usan el mismo vocabulario que la API de Metrocuadrado (venta/arriendo,
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
  # apartamento/casa/...) para no necesitar una capa de traducción.
  class PropertyRequirement < ApplicationRecord
    self.table_name = 'pwb_property_requirements'

    belongs_to :website, class_name: 'Pwb::Website'
    belongs_to :contact, class_name: 'Pwb::Contact', optional: true
    belongs_to :created_by, class_name: 'Pwb::User', optional: true
    has_many :matches, class_name: 'Pwb::PropertyRequirementMatch', dependent: :destroy, inverse_of: :property_requirement

    OPERATION_TYPES = %w[venta arriendo].freeze
    STATUSES = %w[pending running completed failed].freeze

    validates :operation_type, inclusion: { in: OPERATION_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :property_type_key, presence: true
    validates :city, presence: true
    validate :price_range_is_coherent

    scope :pending, -> { where(status: 'pending') }
    scope :for_website, ->(website) { where(website: website) }

    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    def sale?
      operation_type == 'venta'
    end

    def rent?
      operation_type == 'arriendo'
    end

    def mark_running!
      update!(status: 'running')
    end

    def mark_completed!(count:)
      update!(status: 'completed', results_count: count, last_searched_at: Time.current, error_message: nil)
    end

    def mark_failed!(message)
      update!(status: 'failed', error_message: message.to_s.truncate(500), last_searched_at: Time.current)
    end

    private

    def price_range_is_coherent
      return if price_min_cents.blank? || price_max_cents.blank?

      errors.add(:price_max_cents, 'debe ser mayor que el precio mínimo') if price_max_cents < price_min_cents
    end
  end
end
