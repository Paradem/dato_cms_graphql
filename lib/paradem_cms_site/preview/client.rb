# frozen_string_literal: true

module ParademCmsSite
  module Preview
    # Draft-only delivery client. It never reads the published credential, never
    # mutates ENV and never registers a cache/sync query.
    class Client
      ENDPOINT = "https://graphql.datocms.com"

      class HTTP < GraphQL::Client::HTTP
        def initialize(api_token:, environment:)
          super(ENDPOINT)
          @api_token = api_token
          @environment = environment
        end

        def headers(_context)
          {
            "Authorization" => "Bearer #{@api_token}",
            "X-Environment" => @environment,
            "X-Include-Drafts" => "true"
          }
        end

        def connection
          super.tap do |http|
            http.open_timeout = 5
            http.read_timeout = 10
            http.write_timeout = 5
            http.max_retries = 0
          end
        end
      end

      def initialize(configuration:, schema:, environment:, client: nil)
        unless configuration.configured? && configuration.identifier?(environment)
          raise Unavailable, "Preview is not configured for this environment"
        end

        @configuration = configuration
        @graphql = client || GraphQL::Client.new(
          schema: schema,
          execute: HTTP.new(api_token: configuration.api_token_value, environment: environment)
        )
        # Host query fields make each preview document dynamic by design.
        @graphql.allow_dynamic_queries = true if @graphql.respond_to?(:allow_dynamic_queries=)
      end

      # Returns the saved record payload as an underscored hash. The host builds
      # its own unsaved model so nothing is persisted or indexed. Singleton
      # DatoCMS models have no id filter; fetch by locale and verify the id.
      def fetch(model:, root:, fields:, cms_id:, locale:, singleton: false)
        unless @configuration.model?(model) && @configuration.identifier?(cms_id) && @configuration.locale?(locale)
          raise NotFound
        end

        response = @graphql.query(document_for(root, fields, singleton: singleton),
          variables: singleton ? {locale: locale} : {id: cms_id, locale: locale})
        raise Unavailable if response.errors.all.any?

        payload = response.data.to_h.fetch(root)
        raise NotFound if payload.nil?
        raise Unavailable unless payload.is_a?(Hash) && payload["id"] == cms_id

        payload.deep_transform_keys(&:underscore)
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError, JSON::ParserError, KeyError
        raise Unavailable
      end

      private

      def document_for(root, fields, singleton:)
        @documents ||= {}
        @documents[[root, fields, singleton]] ||= @graphql.parse(<<~GRAPHQL)
          #{singleton ? singleton_query(root, fields) : collection_query(root, fields)}
        GRAPHQL
      end

      def collection_query(root, fields)
        <<~GRAPHQL.chomp
          query($id: ItemId!, $locale: SiteLocale!) {
            #{root}(filter: {id: {eq: $id}}, locale: $locale, fallbackLocales: []) {
              #{fields}
            }
          }
        GRAPHQL
      end

      def singleton_query(root, fields)
        <<~GRAPHQL.chomp
          query($locale: SiteLocale!) {
            #{root}(locale: $locale, fallbackLocales: []) {
              #{fields}
            }
          }
        GRAPHQL
      end
    end
  end
end
