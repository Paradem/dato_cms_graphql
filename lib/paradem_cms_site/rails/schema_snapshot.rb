# frozen_string_literal: true

require "json"
require "fileutils"
require "tempfile"
require "graphql/client"
require "dato_cms_graphql/http_transport"

module ParademCmsSite
  # Explicit full-CLI operation, never called by boot, doctor or webhooks.
  class SchemaSnapshot
    # Canada historically allowed DATO_SCHEMA_ENVIRONMENT to select the
    # snapshot while delivery still used DATO_ENVIRONMENT. Preserve that
    # explicit CLI behavior; DATO_ENVIRONMENT remains the canonical choice.
    def self.call(manifest, environment: ENV["DATO_ENVIRONMENT"].presence || ENV["DATO_SCHEMA_ENVIRONMENT"].presence)
      raise ConfigurationError, "Live schema introspection is disabled in CMS fixture mode" if manifest.path_for(:fixture_data)
      transport = DatoCmsGraphql::HTTPTransport.new(include_drafts: false, environment: environment)
      document = GraphQL::Client.dump_schema(transport)
      raise ConfigurationError, "Invalid CMS delivery schema snapshot" unless GraphQL::Client.load_schema(document)
      path = manifest.path_for(:delivery_schema)
      FileUtils.mkdir_p(path.dirname)
      Tempfile.create(["cms-delivery-", ".json"], path.dirname) do |file|
        file.write(JSON.generate(document))
        file.close
        File.rename(file.path, path)
      end
      path
    end
  end
end
