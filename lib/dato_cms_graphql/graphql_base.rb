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

      def plural_name
        to_s.pluralize
      end

      def single_name
        rv = to_s
        rv[0] = rv[0].downcase
        rv
      end

      def parse(query)
        DatoCmsGraphql::Client.parse(query)
      end

      def query_for
        parse <<~GRAPHQL
          query($skip: IntType) {
            items: all#{plural_name}(first: #{graphql_page_size}, skip: $skip) {
              #{fields}
            }
          }
        GRAPHQL
      end

      def query_for_single
        parse <<~GRAPHQL
          query {
            item: #{single_name} {
              #{fields}
            }
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
      @attributes = JSON.parse(attributes.to_json, object_class: OpenStruct)
    end

    def respond_to_missing?(method, *args)
      @attributes.respond_to?(method)
    end

    def method_missing(method, *a, &block)
      if @attributes.respond_to?(method)
        @attributes.send(method, *a, &block)
      else
        super
      end
    end
  end
end
