# frozen_string_literal: true

module ParademCmsSite
  module Preview
    # Short-lived, fully scoped grant. The model and locale come from fixed route
    # defaults, never from submitted preview parameters.
    class Grant
      PURPOSE = "saved_draft_preview"
      SCOPE_KEYS = %w[cms_id environment locale model site_id].freeze
      MAX_TOKEN_BYTES = 4096

      def initialize(configuration:)
        @configuration = configuration
      end

      def issue(cms_id:, locale:, environment:, model:)
        scope = {
          "cms_id" => cms_id,
          "environment" => environment,
          "locale" => locale,
          "model" => model,
          "site_id" => @configuration.site_id_value
        }
        raise ArgumentError, "Invalid preview scope" unless valid_scope?(scope)

        @configuration.message_verifier.generate(scope, purpose: PURPOSE, expires_in: @configuration.ttl_seconds)
      end

      def verify(token, cms_id:, locale:, model:)
        return unless token.is_a?(String) && token.bytesize <= MAX_TOKEN_BYTES

        scope = @configuration.message_verifier.verified(token, purpose: PURPOSE)
        return unless valid_scope?(scope)
        return unless scope["cms_id"] == cms_id && scope["locale"] == locale && scope["model"] == model

        scope
      end

      private

      def valid_scope?(scope)
        @configuration.configured? && scope.is_a?(Hash) && scope.keys.sort == SCOPE_KEYS &&
          @configuration.identifier?(scope["cms_id"]) && @configuration.model?(scope["model"]) &&
          @configuration.locale?(scope["locale"]) && @configuration.identifier?(scope["environment"]) &&
          scope["site_id"] == @configuration.site_id_value
      end
    end
  end
end
