::Bridgetown.initializer :dato_cms_graphql do |config, path_to_queries: nil|
  path_to_queries ||= File.join(Dir.pwd, "plugins", "queries")

  DatoCmsGraphql.path_to_queries = path_to_queries

  config.builder DatoCmsGraphql::Bridgetown::Builder
end
