module DatoCmsGraphql
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "dato_cms_graphql_railtie.configure_rails_initialization" do |app|
        DatoCmsGraphql.path_to_queries = app.root.join("app", "queries")
        puts DatoCmsGraphql.path_to_queries
      end
    end
  end
end
