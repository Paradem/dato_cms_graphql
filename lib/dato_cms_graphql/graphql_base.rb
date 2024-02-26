require_relative "model_iterator"

module DatoCmsGraphql
  class GraphqlBase
    class_attribute :graphql_page_size
    class_attribute :fields
    class_attribute :graphql_single_instance
    class_attribute :bridgetown_render

    class << self
      def page_size(value)
        self.graphql_page_size = value
      end

      def single_instance(value)
        self.graphql_single_instance = value
      end

      def render(value)
        self.bridgetown_render = value
      end

      def query_name
        to_s.humanize.pluralize
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

      def name
        to_s.split("::").last
      end

      def plural_name
        name.pluralize
      end

      def single_name
        rv = name
        rv[0] = rv[0].downcase
        rv
      end

      def parse(query)
        DatoCmsGraphql::Client.parse(query)
      end

      def query_for
        localized_items = I18n.available_locales.map do |locale|
          <<~GRAPHQL
            #{locale}_items: all#{plural_name}(locale: #{locale}, fallbackLocales: [#{I18n.default_locale}"], first: #{graphql_page_size}, skip: $skip) {
              #{fields}
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
            #{locale}_item: #{single_name}(locale: #{locale}, fallbackLocales: [#{I18n.default_locale}"]) {
              #{fields}
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
        new(DatoCmsGraphql.query_one(self::SINGLE))
      end

      def single_instance?
        graphql_single_instance || false
      end

      def render?
        bridgetown_render || false
      end
    end

    attr_reader :attributes
    page_size(100) # Set the maximum page size as default.
    single_instance(false)
    render(true)

    def initialize(attributes)
      @attributes = attributes
    end

    def localized_attributes
      if @attributes.respond_to?(:"#{I18n.locale}_item")
        @attributes.send(:"#{I18n.locale}_item")
      else
        @attributes
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
