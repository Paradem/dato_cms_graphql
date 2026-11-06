# frozen_string_literal: true

require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/inclusion"
require "active_support/core_ext/string/inflections"
require "dato_cms_graphql/fields"
require "dato_cms_graphql/base_query"
require "dato_cms_graphql/client_executor"

module ParademCmsSite
  # Reuse the maintained query DSL, but compile lazily against the installation's
  # local schema/client instead of DatoCmsGraphql's process-global live client.
  class Query < DatoCmsGraphql::BaseQuery
    class << self
      def query_name
        name.split("::").last.delete_suffix("Query")
      end

      def parse(document)
        installation = ParademCmsSite.configuration.installation
        raise ConfigurationError, "Configure the Rails CMS installation first" unless installation
        installation.client.parse(document)
      end

      def initialize_queries(compile: false)
        if compile
          super()
        else
          reset_compilation!
        end
      end

      def const_missing(key)
        expected = single_instance? ? %i[SINGLE] : %i[INDEX META_DATA]
        return super unless expected.include?(key)
        (@compilation_mutex ||= Mutex.new).synchronize do
          initialize_queries(compile: true) unless const_defined?(key, false)
          return const_get(key, false) if const_defined?(key, false)
        end
        super
      end

      def reset_compilation!
        %i[INDEX SINGLE META_DATA].each { |key| remove_const(key) if const_defined?(key, false) }
      end

      # Full CLI regeneration may run after Rails eager loading. Re-evaluate
      # only these owned definitions, resetting inherited DSL defaults first.
      def reload_definition!(path)
        %i[graphql_page_size graphql_single_instance renderable fallback_locale_value fields].each do |attribute|
          public_send("#{attribute}=", superclass.public_send(attribute))
        end
        reset_compilation!
        load path
      end

      def executor
        installation = ParademCmsSite.configuration.installation
        raise ConfigurationError, "Configure the Rails CMS installation first" unless installation
        DatoCmsGraphql::ClientExecutor.new(client: installation.published_client, context: {include_drafts: false})
      end
    end
  end
end
