require "active_support/concern"

module DatoCmsGraphql::Rails
  module CacheTable
    extend ActiveSupport::Concern

    included do
      # New caches use string codes; legacy caches declare a fixed mapping
      # before including this concern, never positions in a reordered locale list.
      mapping = if respond_to?(:dato_cms_locale_mapping)
        dato_cms_locale_mapping
      else
        I18n.available_locales.to_h { |locale| [locale.to_s, locale.to_s] }
      end
      enum :locale, DatoCmsGraphql::Rails::CacheTable.validate_locale_mapping(mapping)
    end

    def self.validate_locale_mapping(mapping)
      unless mapping.is_a?(Hash) && !mapping.empty?
        raise ArgumentError, "CMS locale mapping must be a nonempty hash"
      end
      normalized = mapping.to_h { |key, value| [key.to_s, value.is_a?(String) ? value.dup.freeze : value] }
      valid = normalized.length == mapping.length && normalized.keys.sort == I18n.available_locales.map(&:to_s).sort
      valid &&= normalized.values.uniq.length == normalized.length
      valid &&= normalized.all? { |key, value| value == key } || normalized.values.all? { |value| value.is_a?(Integer) && value >= 0 }
      raise ArgumentError, "CMS locale mapping must explicitly match locales and string or integer storage" unless valid
      normalized.freeze
    end

    class_methods do
      def allow?(type, request)
        permalink = request.params["permalink"]
        exists?(type: type, render: true, permalink: permalink)
      end
    end

    def cms_record
      @parsed ||= begin
        data = read_attribute(:cms_record)
        JSON.parse(data.to_json, object_class: OpenStruct)
      end
    end

    def respond_to_missing?(method, *)
      cms_record.respond_to?(method.to_s, *)
    end

    def method_missing(method, *a, &block)
      if cms_record.respond_to?(method.to_s)
        cms_record.send(method, *a, &block)
      else
        super
      end
    end
  end
end
