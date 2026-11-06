# frozen_string_literal: true

require "json"
require "graphql/client"
require "dato_cms_graphql/http_transport"

module ParademCmsSite
  class ClientFactory
    def initialize(manifest, allow_schema_introspection: false)
      @manifest = manifest
      @allow_schema_introspection = allow_schema_introspection
    end

    def call
      path = @manifest.path_for(:delivery_schema)
      unless path&.file?
        unless @allow_schema_introspection && !@manifest.path_for(:fixture_data)
          raise ConfigurationError, "Supply the local GraphQL delivery schema: #{path.relative_path_from(@manifest.root)}"
        end
        transport = published_transport
        return GraphQL::Client.new(schema: GraphQL::Client.load_schema(transport), execute: transport)
      end
      if @manifest.path_for(:fixture_data)
        resolver = FixtureResolver.new(@manifest)
        schema = GraphQL::Schema.from_definition(path.read, default_resolve: resolver)
        GraphQL::Client.new(schema: schema, execute: schema)
      else
        schema = if path.extname == ".json"
          GraphQL::Client.load_schema(JSON.parse(path.read))
        else
          GraphQL::Schema.from_definition(path.read)
        end
        GraphQL::Client.new(schema: schema, execute: published_transport)
      end
    rescue JSON::ParserError, GraphQL::ParseError
      raise ConfigurationError, "Invalid local CMS schema or fixture JSON"
    end

    private

    def published_transport
      DatoCmsGraphql::HTTPTransport.new(include_drafts: false, environment: ENV["DATO_ENVIRONMENT"])
    end
  end

  class FixtureResolver
    def initialize(manifest)
      @manifest = manifest
      @data = JSON.parse(manifest.path_for(:fixture_data).read)
      valid = @data.is_a?(Hash) && @data.keys.sort == manifest.queries.sort
      valid &&= @data.values.all? do |localized|
        localized.is_a?(Hash) && localized.keys.sort == manifest.locales.sort && localized.values.all? do |rows|
          rows.is_a?(Array) && rows.all? { |row| row.is_a?(Hash) && row["id"].is_a?(String) && !row["id"].strip.empty? }
        end
      end
      raise ConfigurationError, "Fixture data must match the owned models and locales" unless valid
    end

    def call(type, field, object, arguments, _context)
      name = field.graphql_name
      if type.graphql_name == "Query"
        model = @manifest.queries.find do |entry|
          ["all#{entry.pluralize}", "_all#{entry.pluralize}Meta", entry.camelize(:lower)].include?(name)
        end
        raise ConfigurationError, "Unknown fixture query field" unless model
        locale = arguments[:locale]&.to_s || @manifest.locales.first
        rows = @data.fetch(model).fetch(locale)
        if name == "_all#{model.pluralize}Meta"
          {"count" => rows.length}
        elsif name == "all#{model.pluralize}"
          rows.drop(arguments[:skip] || 0).take(arguments[:first] || rows.length)
        else
          rows.first
        end
      elsif name == "_seoMetaTags"
        []
      else
        object[name]
      end
    end
  end
end
