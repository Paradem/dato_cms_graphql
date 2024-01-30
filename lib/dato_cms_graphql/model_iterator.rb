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

    def each
      0.upto(@pages) do |page|
        @results = DatoCmsGraphql.query(@query, variables: {skip: @page_size * page})

        @results.each do |element|
          yield @model.new(element)
        end
      end
    end
  end
end
