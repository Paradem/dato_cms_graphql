require_relative "model_iterator"
require "ostruct"

module DatoCmsGraphql
  class BaseQuery
    class_attribute :graphql_page_size
    class_attribute :fields
    class_attribute :graphql_single_instance
    class_attribute :renderable

    class << self
      def page_size(value)
        self.graphql_page_size = value
      end

      def single_instance(value)
        self.graphql_single_instance = value
      end

      def render(value)
        self.renderable = value
      end

      def graphql_fields(*args)
        self.fields = Fields.new(args).to_query
        initialize_queries
      end

      def initialize_queries
        class_eval do
          const_set(:SINGLE, query_for_single) if single_instance?
          const_set(:INDEX, query_for) unless single_instance?
          const_set(:META_DATA, meta_data_query) unless single_instance?
        end
      end

      def query_name
        name.split("::").last.gsub("Query", "")
      end

      def plural_name
        query_name.pluralize
      end

      def single_name
        query_name.camelize(:lower)
      end

      def parse(query)
        DatoCmsGraphql::Client.parse(query) if defined?(DatoCmsGraphql::Client)
      end

      def query_for
        localized_items = I18n.available_locales.map do |locale|
          <<~GRAPHQL
            #{locale}_items: all#{plural_name}(locale: #{locale}, fallbackLocales: [#{I18n.default_locale}], first: #{graphql_page_size}, skip: $skip) {
              #{fields}

              _seoMetaTags {
                tag
                content
                attributes
              }
            }
          GRAPHQL
        end

        parse <<~GRAPHQL
          query($skip: IntType) {
            #{localized_items.join("\n")}
          }
        GRAPHQL
      end

      def query_for_single
        localized_item = I18n.available_locales.map do |locale|
          <<~GRAPHQL
            #{locale}_item: #{single_name}(locale: #{locale}, fallbackLocales: [#{I18n.default_locale}]) {
              #{fields}

              _seoMetaTags {
                tag
                content
                attributes
              }
            }
          GRAPHQL
        end

        parse <<~GRAPHQL
          query {
            #{localized_item.join("\n")}
          }
        GRAPHQL
      end

      def meta_data_query
        parse <<~GRAPHQL
          query {
            meta_data: _all#{plural_name}Meta {
              count
            }
          }
        GRAPHQL
      end

      def all
        raise "This is a single instance model" if single_instance?
        ModelIterator.new(self)
      end

      def get
        new(DatoCmsGraphql.query(self::SINGLE))
      end

      def single_instance?
        graphql_single_instance || false
      end

      def render?
        renderable || false
      end

      def route
        ":permalink"
      end
    end

    attr_reader :attributes
    page_size(100) # Set the maximum page size as default.
    single_instance(false)
    render(true)

    def route
      self.class.route.gsub(":permalink", permalink)
    end

    def initialize(attributes)
      @raw_attributes = attributes
      @attributes = JSON.parse(attributes.to_json, object_class: OpenStruct)
    end

    def localized_attributes
      if @attributes.respond_to?(:"#{I18n.locale}_item")
        @attributes.send(:"#{I18n.locale}_item")
      else
        @attributes
      end
    end

    def localized_raw_attributes
      if @raw_attributes.has_key?("#{I18n.locale}_item")
        @raw_attributes.dig("#{I18n.locale}_item")
      else
        @raw_attributes
      end
    end

    def respond_to_missing?(method, *args)
      localized_attributes.respond_to?(method)
    end

    def method_missing(method, *a, &block)
      if localized_attributes.respond_to?(method)
        localized_attributes.send(method, *a, &block)
      else
        super
      end
    end
  end
end
