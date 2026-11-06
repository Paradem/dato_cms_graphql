# frozen_string_literal: true

module ParademCmsSite
  # Isolated token-authenticated endpoint: no host login/session/CSRF behavior.
  # Route installation is explicit and belongs to the Rails installer/host.
  class WebhooksController < ActionController::API
    rescue_from WebhookRejected do
      render plain: "Bad Request", status: :bad_request
    end

    def create
      config = ParademCmsSite.configuration
      unless config.webhook_authentication&.call(request)
        render plain: "Unauthorized", status: :unauthorized
        return
      end
      raise ConfigurationError, "Configure the shared CMS sync callable" unless config.sync.respond_to?(:call)
      context = config.webhook_context ? config.webhook_context.call(request) : {}
      if context.nil?
        render plain: "Already processed", status: :ok
        return
      end
      raise ConfigurationError, "Webhook context must be a hash or nil" unless context.is_a?(Hash)
      if RefreshJob.perform_later(context)
        render plain: "OK", status: :ok
      else
        render plain: "Unable to enqueue CMS refresh", status: :service_unavailable
      end
    end
  end
end
