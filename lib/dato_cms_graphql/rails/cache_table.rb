require "active_support/concern"

module DatoCmsGraphql::Rails
  module CacheTable
    extend ActiveSupport::Concern

    included do
      # records.locale is a string column. Map each configured locale to its own
      # string so readers, predicates and scopes round-trip the stored code
      # instead of Rails' default integer mapping for array enums.
      enum :locale, I18n.available_locales.to_h { |locale| [locale.to_s, locale.to_s] }
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

    def respond_to_missing?(method, *args)
      cms_record.respond_to?(method.to_s, *args)
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
