module DatoCmsGraphql
  class GraphqlBase
    class_attribute :graphql_page_size
    class_attribute :fields
    class << self
      def page_size(value)
        self.graphql_page_size = value
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
          const_set(:INDEX, query_for)
          const_set(:META_DATA, meta_data_query)
        end
      end

      def plural_name
        to_s.pluralize
      end

      def parse(query)
        DatoCmsGraphql::Client.parse(query)
      end

      def query_for
        parse <<~GRAPHQL
          query($skip: Int) {
            items: all#{plural_name}(first: #{graphql_page_size}, skip: $skip) {
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
        ModelIterator.new(self)
      end
    end

    attr_reader :attributes
    page_size(100) # Set the maximum page size as default.

    def initialize(attributes)
      @attributes = JSON.parse(attributes.to_json, object_class: OpenStruct)
    end

    def respond_to_missing?(method)
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
