# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "active_support/core_ext/string/inflections"

module DatoCmsGraphql
  class Error < StandardError; end

  # The existing query helpers can use an explicitly supplied GraphQL client,
  # without loading the global boot/introspection entry point or changing ENV.
  class ClientExecutor
    def initialize(client:, context: {})
      @client = client
      @context = context.dup.freeze
    end

    def query(definition, variables: {})
      response = @client.query(definition, variables: variables, context: @context)
      raise Error, "CMS query returned errors" if response.errors.all.any?
      response.data.to_h.deep_transform_keys(&:underscore)
    end

    def count(definition, variables: {})
      value = query(definition, variables: variables).dig("meta_data", "count")
      raise Error, "CMS query returned an invalid count" unless value.is_a?(Integer) && value >= 0
      value
    end
  end
end
