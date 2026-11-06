# frozen_string_literal: true

require "active_support/concern"
require "dato_cms_graphql/rails/cache_table"

module ParademCmsSite
  module CacheRecord
    extend ActiveSupport::Concern

    included do
      include DatoCmsGraphql::Rails::CacheTable

      scope :localized, -> { where(locale: I18n.locale.to_s) }
    end
  end
end
