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
              I18n.available_locales.each do |locale|
                I18n.with_locale(locale) do
                  query.all.each do |item|
                    permalink = "#{locale_path(locale)}#{item.permalink}/"

                    add_resource query.plural_name.underscore, "#{item.id}.erb" do
                      result item
                      permalink permalink
                      title item.title
                      locale locale
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

    def locale_path(locale)
      if locale == I18n.default_locale && !Bridgetown.configuration.prefix_default_locale
        ""
      else
        "#{locale}/"
      end
    end
  end
end
