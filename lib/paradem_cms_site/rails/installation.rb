# frozen_string_literal: true

require_relative "../rails"
require_relative "client_factory"
require_relative "query"
require_relative "cache_record"
require "timeout"
require "socket"
require "openssl"

module ParademCmsSite
  class Installation
    BOOT_RECOVERABLE_ERRORS = [Sync::FetchError, Sync::LockTimeout, DatoCmsGraphql::Error,
      Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError, JSON::ParserError].freeze

    attr_reader :manifest

    def initialize(root:)
      @manifest = Manifest.load(root: root)
      raise ConfigurationError, "Run the Rails CMS install generator first" unless manifest.data["rails"]
      @client_mutex = Mutex.new
    end

    def client
      @client_mutex.synchronize { @client ||= build_client }
    end

    def published_client
      value = client
      if value.execute.is_a?(GraphQL::Client::HTTP)
        require_relative "../published_client"
        PublishedClient.new(client: value, environment: ENV["DATO_ENVIRONMENT"])
      else
        value
      end
    end

    def reset_client!
      @client_mutex.synchronize { @client = nil }
      manifest.queries.each do |name|
        constant = "#{name}Query"
        if Object.const_defined?(constant, false) && !Object.autoload?(constant)
          Object.const_get(constant, false).reset_compilation!
        end
      end
    end

    def reload_queries!
      reset_client!
      query_classes.each { |query| query.reload_definition!(manifest.query_file_for(query.query_name).to_s) }
    end

    def record_class
      manifest.data.fetch("rails").fetch("cache_model").constantize
    end

    def query_classes
      manifest.queries.map { |name| "#{name}Query".constantize }
    end

    def configure!
      if manifest.path_for(:fixture_data) && ::Rails.env.production?
        raise ConfigurationError, "CMS fixture mode is development/test only"
      end
      I18n.available_locales = manifest.locales
      I18n.default_locale = manifest.locales.first unless manifest.locales.include?(I18n.default_locale.to_s)
      reset_client!
      ParademCmsSite.configure do |config|
        config.installation = self
        config.sync = ->(context) { refresh(context) }
        strategy = manifest.data.fetch("rails").fetch("webhook")
        config.webhook_authentication = unless strategy == "disabled"
          WebhookAuthentication.public_send(strategy, secret: -> { ENV["DATO_WEBHOOK_SECRET"] })
        end
      end
      self
    end

    def refresh(context = {})
      config = ParademCmsSite.configuration
      Sync.new(manifest: manifest, queries: query_classes, client: -> { client }, record_class: record_class,
        environment: ENV["DATO_ENVIRONMENT"],
        within_transaction: ->(result) { config.within_transaction&.call(result, context) },
        after_sync: ->(result) { config.after_sync&.call(result, context) }).call
    end

    private

    def build_client
      ClientFactory.new(manifest,
        allow_schema_introspection: manifest.data.fetch("rails").fetch("allow_schema_introspection", false)).call
    end

    public

    def boot!
      ParademCmsSite.refresh("source" => "boot")
    rescue *BOOT_RECOVERABLE_ERRORS => error
      raise unless manifest.data.fetch("rails").fetch("boot_fallback", false) && record_class.exists?
      ::Rails.logger.error("CMS refresh failed at boot; retaining the published cache (#{error.class})")
      RefreshJob.perform_later("source" => "boot_retry")
    end
  end
end
