# frozen_string_literal: true

require_relative "../paradem_cms_site"
require "graphql/client"
require "graphql/client/http"

module ParademCmsSite
  # Snapshot the existing client's published headers for one refresh. Do not
  # change global ENV, constants, query definitions or the source transport.
  class PublishedClient
    class SnapshotHTTP < GraphQL::Client::HTTP
      def initialize(source, headers)
        super(source.uri.to_s)
        @source = source
        @headers = headers
      end

      def headers(_context)
        @headers.dup
      end

      def connection
        unless @source.uri == uri
          raise ConfigurationError, "CMS endpoint changed during a published refresh"
        end
        @source.connection
      end
    end
    private_constant :SnapshotHTTP

    def initialize(client:, environment:)
      source = client.execute
      unless source.is_a?(GraphQL::Client::HTTP)
        raise ConfigurationError, "Published client requires a GraphQL HTTP transport"
      end
      unless environment.nil? || environment.is_a?(String)
        raise ConfigurationError, "CMS environment must be a string or nil"
      end
      environment = nil if environment&.strip&.empty?
      headers = source.headers(include_drafts: false)
      if headers.keys.any? { |key| key.to_s.casecmp?("X-Include-Drafts") }
        raise ConfigurationError, "CMS transport must omit draft headers for a published refresh"
      end
      environments = headers.select { |key, _| key.to_s.casecmp?("X-Environment") }.values
      unless environments == (environment ? [environment] : [])
        raise ConfigurationError, "CMS transport does not match the configured environment"
      end
      headers = headers.to_h { |key, value| [key.to_s.dup.freeze, value.to_s.dup.freeze] }.freeze
      @client = GraphQL::Client.new(schema: client.schema, execute: SnapshotHTTP.new(source, headers))
    end

    def query(definition, variables: {}, context: {})
      @client.query(definition, variables: variables, context: context.merge(include_drafts: false))
    end
  end
end
