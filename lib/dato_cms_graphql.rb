# frozen_string_literal: true

require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/inclusion"
require "active_support/core_ext/hash/keys"

require "graphql/client"
require "graphql/client/http"

require_relative "dato_cms_graphql/version"
require_relative "dato_cms_graphql/fields"
require_relative "dato_cms_graphql/base_query"

require_relative "test_schema"

if defined?(::Rails)
  require_relative "dato_cms_graphql/rails/routing"
  require_relative "dato_cms_graphql/rails/persistence"
  require_relative "dato_cms_graphql/rails/cache_table"
  require_relative "dato_cms_graphql/rails/railtie"
end

if defined?(::Bridgetown)
  require_relative "dato_cms_graphql/bridgetown/query_builder"
  require_relative "dato_cms_graphql/bridgetown/initializer"
end

module DatoCmsGraphql
  class Error < StandardError; end

  if ENV["TEST"] == "true"
    Client = GraphQL::Client.new(schema: TestSchema, execute: TestSchema)
  elsif ENV["DATO_API_TOKEN"].present?
    HTTP = GraphQL::Client::HTTP.new("https://graphql.datocms.com") do
      def headers(context)
        {
          "Authorization" => ENV["DATO_API_TOKEN"].to_s,
          "Accept" => "application/json",
          "Content-Type" => "application/json",
          "X-Include-Drafts" => ENV["DATO_API_INCLUDE_DRAFTS"].present?
        }
      end
    end

    Schema = GraphQL::Client.load_schema(HTTP)
    Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
  else
    puts "DATO_API_TOKEN not present"
  end

  def self.query(query, variables: {})
    Client.query(query, variables: variables).data.to_h.deep_transform_keys(&:underscore)
  end

  def self.count(query, variables: {})
    Client.query(query, variables: variables).data.meta_data.count
  end

  def self.queries
    @queries ||= begin
      raise "DatoCmsGraphql.path_to_queries has not been set with the path to your queries" if path_to_queries.nil?
      raise "\"#{path_to_queries}\" does not exist" unless File.exist?(path_to_queries)

      Dir[File.join(path_to_queries, "*.rb")].sort.each { require(_1) }
      ObjectSpace.each_object(::Class)
        .select { |klass| klass < DatoCmsGraphql::BaseQuery }
        .group_by(&:name).values.map { |values| values.max_by(&:object_id) }
        .flatten
    end
  end

  def self.path_to_queries
    @path_to_queries
  end

  def self.path_to_queries=(value)
    @path_to_queries = value
  end

  def self.renderable
    queries.select(&:render?)
  end
end
