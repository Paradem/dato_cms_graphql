module DatoCmsGraphql::Rails
  module Routing
    def self.draw_routes(base_class)
      ::Rails.application.routes.draw do
        scope "(:locale)", locale: I18n.default_locale do
          # Queries that represent collections of pages.
          DatoCmsGraphql.renderable.select { |q| !q.route.blank? }.each do |query|
            controller = query.plural_name.underscore
            get(
              query.route,
              to: "#{controller}#show",
              constraints: lambda { |request| base_class.allow?(query.query_name, request) }
            )
          end

          home = DatoCmsGraphql.renderable.find { |q| q.route.blank? }
          root "#{home.plural_name.underscore}#show"
        end
      end
    end
  end
end
