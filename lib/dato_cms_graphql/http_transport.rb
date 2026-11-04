# frozen_string_literal: true

require "graphql/client/http"

module DatoCmsGraphql
  # Shared delivery/introspection headers. Loading or constructing this transport
  # does not load a schema or contact DatoCMS.
  class HTTPTransport < GraphQL::Client::HTTP
    DEFAULT_ENDPOINT = "https://graphql.datocms.com"

    def initialize(endpoint = DEFAULT_ENDPOINT, include_drafts: nil, environment: -> { ENV["DATO_ENVIRONMENT"] })
      unless [true, false, nil].include?(include_drafts)
        raise ArgumentError, "include_drafts must be true, false or nil"
      end
      @include_drafts = include_drafts
      @environment = environment
      super(endpoint)
    end

    def headers(context)
      drafts = @include_drafts.nil? ? (context || {}).fetch(:include_drafts) { ENV["DATO_API_INCLUDE_DRAFTS"] == "true" } : @include_drafts
      result = {
        "Authorization" => ENV.fetch("DATO_API_TOKEN"),
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "X-Base-Editing-Url" => "https://#{ENV["PROJECT"]}.admin.datocms.com"
      }
      # DatoCMS rejects a false header. Only explicit true enables drafts;
      # published requests must omit the header, even with preview ENV enabled.
      result["X-Include-Drafts"] = "true" if drafts == true
      environment = @environment.respond_to?(:call) ? @environment.call : @environment
      result["X-Environment"] = environment if environment && !environment.strip.empty?
      result
    end
  end
end
