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
      results["#{I18n.locale}_items"].each do |element|
        yield @model.new(element)
      end
    end

    private

    def results
      @results ||= (0..@pages).each_with_object({}) do |page, rs|
        res_page = DatoCmsGraphql.query(@query, variables: {skip: @page_size * page})

        res_page.each do |k, v|
          rs[k] ||= []
          rs[k].concat(v)
        end
      end
    end
  end
end
