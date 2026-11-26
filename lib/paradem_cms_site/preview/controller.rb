# frozen_string_literal: true

module ParademCmsSite
  module Preview
    # Host controllers own routes, templates and model construction. This concern
    # owns the security boundary: fail closed, verify the grant before any network
    # call, and forbid caching, indexing, framing and conditional 304s.
    module Controller
      extend ActiveSupport::Concern

      included do
        before_action :protect_preview_response
        before_action :require_preview_configuration
        before_action :authenticate_preview_grant
        rescue_from ParademCmsSite::Preview::NotFound, with: :render_preview_missing
        rescue_from ParademCmsSite::Preview::Unavailable, with: :render_preview_unavailable
      end

      private

      attr_reader :preview_scope

      def preview_configuration
        ParademCmsSite.configuration.preview
      end

      def preview_model
        request.path_parameters.fetch(:model)
      end

      def preview_grant
        @preview_grant ||= ParademCmsSite::Preview::Grant.new(configuration: preview_configuration)
      end

      def preview_client
        @preview_client ||= ParademCmsSite::Preview::Client.new(
          configuration: preview_configuration,
          schema: preview_schema,
          environment: preview_scope.fetch("environment")
        )
      end

      def preview_schema
        installation = ParademCmsSite.configuration.installation
        raise ConfigurationError, "Configure the Rails CMS installation before preview" unless installation

        installation.client.schema
      end

      # Returns an underscored payload hash for the host to build an unsaved record.
      def preview_record(model:, fields:, root: model)
        preview_client.fetch(
          model: model,
          root: root,
          fields: fields,
          cms_id: preview_scope.fetch("cms_id"),
          locale: preview_scope.fetch("locale")
        )
      end

      def require_preview_configuration
        render_preview_error(:unavailable, :service_unavailable) unless preview_configuration.configured?
      end

      def authenticate_preview_grant
        @preview_scope = preview_grant.verify(
          params[:token],
          cms_id: params[:cms_id],
          locale: params[:locale],
          model: preview_model
        )
        render_preview_error(:invalid, :unauthorized) unless @preview_scope
      end

      def render_preview_missing
        render_preview_error(:missing, :not_found)
      end

      def render_preview_unavailable
        render_preview_error(:unavailable, :service_unavailable)
      end

      # Override for localized host templates.
      def render_preview_error(kind, status)
        render plain: "Preview #{kind}", status: status, content_type: "text/plain"
      end

      def protect_preview_response
        # Rack's conditional GET middleware otherwise answers 304 for no-store HTML.
        request.env.delete("HTTP_IF_NONE_MATCH")
        request.env.delete("HTTP_IF_MODIFIED_SINCE")
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = "frame-ancestors 'none'"
      end
    end
  end
end
