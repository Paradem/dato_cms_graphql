# frozen_string_literal: true

require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/inclusion"
require "active_support/core_ext/hash/keys"

require "graphql/client"
require "graphql/client/http"

require_relative "dato_cms_graphql/version"
require_relative "dato_cms_graphql/fields"
require_relative "dato_cms_graphql/graphql_base"

require_relative "test_schema"

module DatoCmsGraphql
  class Error < StandardError; end

  if ENV["TEST"] == "true"
    Client = GraphQL::Client.new(schema: TestSchema, execute: TestSchema)
  else
    HTTP = GraphQL::Client::HTTP.new("https://graphql.datocms.com") do
      def headers(context)
        {
          "Authorization" => ENV["DATO_API_TOKEN"].to_s,
          "Accept" => "application/json",
          "Content-Type" => "application/json",
          "X-Include-Drafts" => true
        }
      end
    end

    Schema = GraphQL::Client.load_schema(HTTP)
    Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
  end

  def self._query(query, variables: {})
    response = Client.query(query, variables: variables)
    response.data.items
  end

  def self.query(query, variables: {})
    Client.query(query, variables: variables).data.items.map do |result|
      result.to_h.deep_transform_keys { |k| k.underscore }
    end
  end

  def self.query_one(query, variables: {})
    Client.query(query, variables: variables).data.item.to_h.deep_transform_keys { |k| k.underscore }
  end

  def self.count(query, variables: {})
    Client.query(query, variables: variables).data.meta_data.count
  end
end
