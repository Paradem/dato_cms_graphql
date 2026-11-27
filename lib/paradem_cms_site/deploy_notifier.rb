# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module ParademCmsSite
  # Reports a DatoCMS deployment result to the project's deploy-result webhook.
  # The endpoint token is configuration, never source. Notification failures are
  # logged without the URL and never fail the cache refresh that triggered them.
  class DeployNotifier
    ENV_KEY = "DATO_DEPLOY_RESULT_URL"
    DEFAULT_TIMEOUT = 5

    def self.call(status:, url: ENV[ENV_KEY], timeout: DEFAULT_TIMEOUT, logger: nil)
      new(url: url, timeout: timeout, logger: logger).call(status: status)
    end

    def initialize(url:, timeout: DEFAULT_TIMEOUT, logger: nil)
      unless timeout.is_a?(Numeric) && timeout.real? && timeout.finite? && timeout.positive?
        raise ConfigurationError, "Deploy notifier timeout must be a positive number"
      end

      @url = url
      @timeout = timeout
      @logger = logger
    end

    def call(status:)
      endpoint = resolve(@url).to_s
      if endpoint.strip.empty?
        report("endpoint is not configured")
        return false
      end

      uri = URI.parse(endpoint)
      unless uri.is_a?(URI::HTTPS) && uri.host
        report("endpoint must be an HTTPS URL")
        return false
      end

      response = perform(uri, status)
      return true if response.is_a?(Net::HTTPSuccess)

      report("provider returned HTTP #{response.code}")
      false
    rescue URI::InvalidURIError
      report("endpoint is invalid")
      false
    rescue => error
      report("transport failed (#{error.class})")
      false
    end

    private

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end

    def perform(uri, status)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(status: status)
      http.start { |connection| connection.request(request) }
    end

    def report(reason)
      logger = @logger || (::Rails.logger if defined?(::Rails) && ::Rails.respond_to?(:logger))
      logger&.warn("DatoCMS deploy result notification skipped or failed: #{reason}")
    end
  end
end
