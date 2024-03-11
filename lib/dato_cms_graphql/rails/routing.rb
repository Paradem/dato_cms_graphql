module DatoCmsGraphql::Rails::Routing
  def self.draw_routes(base_class)
    ::Rails.application.routes.draw do
      scope "(:locale)", locale: I18n.default_locale do
        # Queries that represent collections of pages.
        DatoCmsGraphql.renderable.each do |query|
          controller = query.plural_name.underscore

          if query.route.blank?
            root "#{controller}#show"
          else
            get(
              query.route,
              to: "#{controller}#show",
              constraints: lambda { |request| base_class.allow?(query.query_name, request) }
            )
          end
        end
      end
    end
  end
end
