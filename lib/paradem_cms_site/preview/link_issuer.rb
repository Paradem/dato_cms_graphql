# frozen_string_literal: true

module ParademCmsSite
  module Preview
    # Browser-to-server issuer for the official DatoCMS Web Previews plugin.
    # Header authentication, not Rails session cookies. The host supplies the
    # route path and label through `link_builder`.
    module LinkIssuer
      extend ActiveSupport::Concern

      included do
        before_action :protect_preview_links_response
        before_action :require_preview_configuration
        before_action :allow_preview_plugin_origin
        before_action :authenticate_preview_issuer, only: :create
        rescue_from ActionDispatch::Http::Parameters::ParseError do
          protect_preview_links_response
          render_preview_link_error("invalid_json", :bad_request)
        end
      end

      def preflight
        requested = request.headers["Access-Control-Request-Headers"].to_s.downcase.split(",").map(&:strip)
        unless request.headers["Origin"] == preview_plugin_origin &&
            request.headers["Access-Control-Request-Method"] == "POST" &&
            (requested - %w[content-type x-dato-preview-secret]).empty?
          return render_preview_link_error("invalid_preflight", :forbidden)
        end

        response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Dato-Preview-Secret"
        response.headers["Access-Control-Max-Age"] = "600"
        head :no_content
      end

      def create
        return render_preview_link_error("json_required", :unsupported_media_type) unless request.media_type == "application/json"

        payload = request.request_parameters
        environment = payload["environmentId"]
        # The editor's environment comes from the plugin; it is format-validated
        # and bound into the grant. The draft token remains the access boundary.
        unless payload["siteId"] == preview_configuration.site_id_value &&
            preview_configuration.locale?(payload["locale"]) &&
            preview_configuration.identifier?(environment)
          return render_preview_link_error("invalid_scope", :unprocessable_content)
        end

        model = payload.dig("itemType", "attributes", "api_key") if payload["itemType"].is_a?(Hash) && payload["itemType"]["attributes"].is_a?(Hash)
        return render_preview_link_error("invalid_model", :unprocessable_content) unless model.is_a?(String)
        return render json: {previewLinks: []} unless preview_configuration.model?(model)

        cms_id = payload["item"]["id"] if payload["item"].is_a?(Hash)
        return render json: {previewLinks: []} if cms_id.nil?
        return render_preview_link_error("invalid_record", :unprocessable_content) unless preview_configuration.identifier?(cms_id)

        locale = payload.fetch("locale")
        token = ParademCmsSite::Preview::Grant.new(configuration: preview_configuration).issue(
          cms_id: cms_id, locale: locale, model: model, environment: environment
        )
        link = preview_configuration.link_builder.call(model: model, locale: locale, cms_id: cms_id, token: token)
        render json: {previewLinks: [{
          label: link.fetch(:label),
          url: "#{preview_configuration.base_url_value}#{link.fetch(:path)}"
        }]}
      end

      private

      def preview_configuration
        ParademCmsSite.configuration.preview
      end

      def preview_plugin_origin
        preview_configuration.plugin_origin
      end

      def protect_preview_links_response
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Vary"] = "Origin"
      end

      def require_preview_configuration
        configured = preview_configuration.configured? && preview_configuration.link_builder.respond_to?(:call)
        render_preview_link_error("preview_unavailable", :service_unavailable) unless configured
      end

      def allow_preview_plugin_origin
        origin = request.headers["Origin"]
        if origin.present? && origin != preview_plugin_origin
          render_preview_link_error("origin_not_allowed", :forbidden)
        elsif origin == preview_plugin_origin
          response.headers["Access-Control-Allow-Origin"] = origin
        end
      end

      def authenticate_preview_issuer
        credential = request.headers["X-Dato-Preview-Secret"]
        expected = preview_configuration.secret_value
        unless credential.present? && ActiveSupport::SecurityUtils.secure_compare(expected, credential)
          render_preview_link_error("unauthorized", :unauthorized)
        end
      end

      def render_preview_link_error(code, status)
        render json: {error: code}, status: status
      end
    end
  end
end
