# frozen_string_literal: true

require "active_support/core_ext/hash/keys"
require "active_support/core_ext/time/calculations"
require "graphql/client"
require "graphql/client/http"
require "uri"

module ParademCmsSite
  # Saved-draft preview: its own draft-only credential, an explicit environment
  # bound into a short-lived signed grant, and no access to the published client.
  module Preview
    class NotFound < StandardError; end
    class Unavailable < StandardError; end

    IDENTIFIER = /\A[A-Za-z0-9_-]{1,128}\z/
    PLUGIN_ORIGIN = "https://plugins-cdn.datocms.com"

    # Per-project settings. Values may be callables (e.g. ENV lookups) so an
    # unconfigured deployment fails closed at request time instead of at boot.
    class Configuration
      attr_accessor :enabled, :site_id, :secret, :api_token, :base_url, :models, :locales, :ttl,
        :verifier, :plugin_origin, :link_builder

      def initialize
        @enabled = false
        @models = []
        @locales = []
        @ttl = 900
        @plugin_origin = PLUGIN_ORIGIN
      end

      def configured?
        return false unless enabled == true

        raw_secret = secret_value
        raw_token = api_token_value
        raw_secret.is_a?(String) && raw_secret.ascii_only? && raw_secret.bytesize.between?(32, 512) &&
          !raw_secret.match?(/\s/) &&
          raw_token.is_a?(String) && !raw_token.empty? && raw_token.ascii_only? && !raw_token.match?(/\s/) &&
          identifier?(site_id_value) &&
          models.is_a?(Array) && models.any? && models.uniq == models && models.all? { |model| identifier?(model) } &&
          locales.is_a?(Array) && locales.any? && locales.uniq == locales && locales.all? { |locale| identifier?(locale) } &&
          ttl_seconds.positive? && verifier? && valid_base_url?
      end

      def identifier?(value)
        value.is_a?(String) && value.match?(IDENTIFIER)
      end

      def model?(value)
        models.include?(value)
      end

      def locale?(value)
        locales.include?(value)
      end

      def secret_value = resolve(secret)
      def api_token_value = resolve(api_token)
      def site_id_value = resolve(site_id)
      def base_url_value = resolve(base_url).to_s.delete_suffix("/")
      def message_verifier = resolve(verifier)
      def ttl_seconds = ttl.to_i

      def valid_base_url?
        uri = URI.parse(base_url_value)
        transport_allowed = uri.scheme == "https" ||
          (!production? && uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host))
        transport_allowed && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.empty?
      rescue URI::InvalidURIError
        false
      end

      private

      def resolve(value)
        value.respond_to?(:call) ? value.call : value
      end

      def verifier?
        message_verifier.respond_to?(:generate) && message_verifier.respond_to?(:verified)
      end

      def production?
        defined?(::Rails) ? ::Rails.env.production? : false
      end
    end
  end
end

require_relative "preview/grant"
require_relative "preview/client"
