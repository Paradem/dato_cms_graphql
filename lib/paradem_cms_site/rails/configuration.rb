# frozen_string_literal: true

module ParademCmsSite
  class WebhookRejected < StandardError; end

  class Configuration
    attr_accessor :sync, :webhook_authentication, :webhook_context, :installation, :within_transaction, :after_sync, :on_error

    def refresh(context = {})
      raise ConfigurationError, "Configure the shared CMS sync callable" unless sync.respond_to?(:call)
      raise ConfigurationError, "CMS refresh context must be a hash" unless context.is_a?(Hash)
      begin
        sync.call(context)
      rescue => error
        begin
          on_error&.call(error, context)
        rescue => hook_error
          ActiveSupport.error_reporter.report(hook_error, source: "paradem_cms_site.on_error")
        end
        raise error
      end
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def refresh(context = {})
      configuration.refresh(context)
    end
  end
end
