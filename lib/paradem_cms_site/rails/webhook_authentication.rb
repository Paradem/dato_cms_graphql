# frozen_string_literal: true

require "openssl"
require "active_support/security_utils"
require "active_support/core_ext/object/blank"

module ParademCmsSite
  class WebhookAuthentication
    def self.shared_header(secret:, header: "Webhook-Auth")
      new(secret: secret, header: header, hmac: false)
    end

    def self.hmac_sha256(secret:, header: "X-DATO-Signature")
      new(secret: secret, header: header, hmac: true)
    end

    def initialize(secret:, header:, hmac:)
      @secret = secret
      @header = header
      @hmac = hmac
    end

    def call(request)
      secret = @secret.respond_to?(:call) ? @secret.call : @secret
      supplied = request.headers[@header]
      return false unless secret.is_a?(String) && secret.present? && supplied.is_a?(String) && supplied.present?
      expected = @hmac ? "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)}" : secret
      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    end
  end
end
