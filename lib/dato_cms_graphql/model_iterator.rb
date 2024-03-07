module DatoCmsGraphql
  class ModelIterator
    include Enumerable

    delegate :each, :[], to: :localized_results

    def initialize(model)
      @model = model
      @query = model::INDEX
      @count = DatoCmsGraphql.count(model::META_DATA)
      @page_size = model.graphql_page_size

      @pages = @count / @page_size + ((@count % @page_size).positive? ? 1 : 0)
    end

    private

    def localized_results
      results["#{I18n.locale}_items"]
    end

    def results
      @results ||= (0..@pages).each_with_object({}) do |page, rs|
        res_page = DatoCmsGraphql.query(@query, variables: {skip: @page_size * page})

        res_page.each do |k, v|
          v = v.map { |m| @model.new(m) }

          rs[k] ||= []
          rs[k].concat(v)
        end
      end
    end
  end
end
