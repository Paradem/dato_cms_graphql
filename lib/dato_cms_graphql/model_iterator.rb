module DatoCmsGraphql
  class ModelIterator
    include Enumerable

    def initialize(model)
      @model = model
      @query = model::INDEX
      @count = DatoCmsGraphql.count(model::META_DATA)
      @page_size = model.graphql_page_size

      @pages = @count / @page_size + ((@count % @page_size).positive? ? 1 : 0)
    end

    def count
      @count
    end

    def each
      return to_enum(:each) unless block_given?

      (0..@pages).each do |page|
        res_page = DatoCmsGraphql.query(@query, variables: {skip: @page_size * page})

        items = res_page["#{I18n.locale}_items"]
        next unless items

        items.each do |raw|
          yield @model.new(raw)
        end
      end
    end
  end
end
