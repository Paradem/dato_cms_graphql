module DatoCmsGraphql
  class ModelIterator
    include Enumerable

    def initialize(model, executor: DatoCmsGraphql)
      @model = model
      @executor = executor
      @query = model::INDEX
      @count = @executor.count(model::META_DATA)
      @page_size = model.graphql_page_size

      @pages = @count / @page_size + ((@count % @page_size).positive? ? 1 : 0)
    end

    attr_reader :count

    # Older consumers exposed Array-style indexing through their iterator.
    # Preserve that result API without changing the streaming each path.
    def [](...)
      to_a.[](...)
    end

    def each
      return to_enum(:each) unless block_given?

      (0..@pages).each do |page|
        res_page = @executor.query(@query, variables: {skip: @page_size * page})

        items = res_page["#{I18n.locale}_items"]
        next unless items

        items.each do |raw|
          yield @model.new(raw)
        end
      end
    end
  end
end
