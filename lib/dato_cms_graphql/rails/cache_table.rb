require "active_support/concern"

module DatoCmsGraphql::Rails::CacheTable
  extend ActiveSupport::Concern

  included do
    enum :locale, I18n.available_locales
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
