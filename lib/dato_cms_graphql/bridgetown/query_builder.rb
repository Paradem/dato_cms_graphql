module DatoCmsGraphql::Bridgetown
  class Builder < ::Bridgetown::Builder
    def build
      queries = DatoCmsGraphql.queries

      hook :site, :post_read do
        queries.each do |query|
          if query.single_instance?
            site.data[query.single_name.underscore] = query.get
          else
            results = query.all
            site.data[query.plural_name.underscore] = results

            if query.render?
              results.each do |item|
                add_resource query.plural_name.underscore, "#{item.id}.erb" do
                  result item
                  permalink "#{item.permalink}/"
                  title item.title
                  layout query.single_name.underscore
                  content ""
                end
              end
            end
          end
        end
      end
    end
  end
end
