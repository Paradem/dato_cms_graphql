module DatoCmsGraphql
  module Rails
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.join(__dir__, "cache_task.rake")
      end
      initializer "dato_cms_graphql_railtie.configure_rails_initialization" do |app|
        DatoCmsGraphql.path_to_queries = app.root.join("app", "queries")
      end
    end
  end
end
