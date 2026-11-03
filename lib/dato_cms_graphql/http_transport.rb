# frozen_string_literal: true

require "graphql/client/http"

module DatoCmsGraphql
  # Shared delivery/introspection headers. Loading or constructing this transport
  # does not load a schema or contact DatoCMS.
  class HTTPTransport < GraphQL::Client::HTTP
    DEFAULT_ENDPOINT = "https://graphql.datocms.com"

    def initialize(endpoint = DEFAULT_ENDPOINT)
      super
    end

    def headers(context)
      drafts = (context || {}).fetch(:include_drafts) { ENV["DATO_API_INCLUDE_DRAFTS"] == "true" }
      result = {
        "Authorization" => ENV.fetch("DATO_API_TOKEN"),
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "X-Base-Editing-Url" => "https://#{ENV["PROJECT"]}.admin.datocms.com"
      }
      # DatoCMS rejects a false header. Only explicit true enables drafts;
      # published requests must omit the header, even with preview ENV enabled.
      result["X-Include-Drafts"] = "true" if drafts == true
      environment = ENV["DATO_ENVIRONMENT"]
      result["X-Environment"] = environment if environment && !environment.strip.empty?
      result
    end
  end
end
