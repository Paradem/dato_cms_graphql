# frozen_string_literal: true

require_relative "test_helper"
require "active_support/message_verifier"
require "paradem_cms_site/rails/configuration"

class PreviewTest < Minitest::Test
  Response = Struct.new(:data, :errors)
  Errors = Struct.new(:all)

  class FakeGraphQL
    attr_reader :documents, :variables

    def initialize(response)
      @response = response
      @documents = []
    end

    def parse(document)
      @documents << document
      document
    end

    def query(_document, variables:)
      @variables = variables
      @response
    end
  end

  def setup
    @configuration = ParademCmsSite::Preview::Configuration.new
    @configuration.enabled = true
    @configuration.site_id = "196903"
    @configuration.secret = "preview-secret-" + "a" * 32
    @configuration.api_token = "draft-read-only-token"
    @configuration.base_url = "https://preview.example.com"
    @configuration.models = %w[article page homepage]
    @configuration.locales = %w[en fr]
    @configuration.ttl = 900
    @configuration.verifier = ActiveSupport::MessageVerifier.new("v" * 64, digest: "SHA256")
  end

  def grant
    ParademCmsSite::Preview::Grant.new(configuration: @configuration)
  end

  def client(graphql)
    ParademCmsSite::Preview::Client.new(configuration: @configuration, schema: nil, environment: "main-1", client: graphql)
  end

  def test_configuration_requires_every_project_setting
    assert @configuration.configured?
    assert_equal "https://preview.example.com", @configuration.base_url_value

    invalid = [
      ->(config) { config.enabled = false },
      ->(config) { config.secret = "short" },
      ->(config) { config.secret = "has whitespace " + "a" * 32 },
      ->(config) { config.api_token = "" },
      ->(config) { config.site_id = "../other" },
      ->(config) { config.base_url = "http://preview.example.com" },
      ->(config) { config.base_url = "https://preview.example.com/path" },
      ->(config) { config.models = [] },
      ->(config) { config.models = %w[article article] },
      ->(config) { config.locales = [] },
      ->(config) { config.ttl = 0 },
      ->(config) { config.verifier = nil }
    ]
    invalid.each do |change|
      config = clone_configuration
      change.call(config)
      refute config.configured?
    end
  end

  def test_configuration_resolves_callables_and_allows_loopback_http_locally
    config = clone_configuration
    config.secret = -> { "preview-secret-" + "b" * 32 }
    config.base_url = -> { "http://localhost:3000/" }
    assert config.configured?
    assert_equal "http://localhost:3000", config.base_url_value
  end

  def test_grant_round_trips_and_rejects_any_scope_mismatch
    token = grant.issue(cms_id: "draft-1", locale: "en", environment: "main-1", model: "article")
    scope = grant.verify(token, cms_id: "draft-1", locale: "en", model: "article")
    assert_equal({"cms_id" => "draft-1", "environment" => "main-1", "locale" => "en",
                  "model" => "article", "site_id" => "196903"}, scope)

    assert_nil grant.verify(token, cms_id: "draft-2", locale: "en", model: "article")
    assert_nil grant.verify(token, cms_id: "draft-1", locale: "fr", model: "article")
    assert_nil grant.verify(token, cms_id: "draft-1", locale: "en", model: "page")
    assert_nil grant.verify(nil, cms_id: "draft-1", locale: "en", model: "article")
    assert_nil grant.verify([token], cms_id: "draft-1", locale: "en", model: "article")
    assert_nil grant.verify(token + "x", cms_id: "draft-1", locale: "en", model: "article")
    assert_nil grant.verify("y" * 5000, cms_id: "draft-1", locale: "en", model: "article")

    other_site = clone_configuration
    other_site.site_id = "999"
    assert_nil ParademCmsSite::Preview::Grant.new(configuration: other_site)
      .verify(token, cms_id: "draft-1", locale: "en", model: "article")

    assert_raises(ArgumentError) { grant.issue(cms_id: "draft-1", locale: "en", environment: "../evil", model: "article") }
    assert_raises(ArgumentError) { grant.issue(cms_id: "draft-1", locale: "de", environment: "main-1", model: "article") }
    assert_raises(ArgumentError) { grant.issue(cms_id: "draft-1", locale: "en", environment: "main-1", model: "global") }
  end

  def test_grant_expires_and_fails_closed_when_configuration_is_incomplete
    @configuration.ttl = 1
    token = grant.issue(cms_id: "draft-1", locale: "en", environment: "main-1", model: "article")
    sleep 1.1
    assert_nil grant.verify(token, cms_id: "draft-1", locale: "en", model: "article")

    @configuration.ttl = 900
    token = grant.issue(cms_id: "draft-1", locale: "en", environment: "main-1", model: "article")
    @configuration.base_url = nil
    assert_nil grant.verify(token, cms_id: "draft-1", locale: "en", model: "article")
  end

  def test_draft_transport_sends_only_the_preview_credential_and_explicit_headers
    headers = ParademCmsSite::Preview::Client::HTTP.new(api_token: "draft-token", environment: "main-2").headers({})
    assert_equal "Bearer draft-token", headers.fetch("Authorization")
    assert_equal "main-2", headers.fetch("X-Environment")
    assert_equal "true", headers.fetch("X-Include-Drafts")
  end

  def test_fetch_returns_underscored_payload_and_never_accepts_another_id
    graphql = FakeGraphQL.new(Response.new({"article" => {"id" => "draft-1", "someField" => "saved"}}, Errors.new([])))
    payload = client(graphql).fetch(model: "article", root: "article", fields: "id title", cms_id: "draft-1", locale: "en")
    assert_equal({"id" => "draft-1", "some_field" => "saved"}, payload)
    document = graphql.documents.first
    assert_includes document, "article(filter: {id: {eq: $id}}, locale: $locale, fallbackLocales: [])"
    assert_includes document, "id title"
    assert_equal 1, graphql.documents.length
    assert_equal({id: "draft-1", locale: "en"}, graphql.variables)
  end

  def test_fetch_supports_singleton_models_by_locale_and_verifies_the_id
    graphql = FakeGraphQL.new(Response.new({"homepage" => {"id" => "draft-1", "someField" => "saved"}}, Errors.new([])))
    payload = client(graphql).fetch(model: "homepage", root: "homepage", fields: "id title",
      cms_id: "draft-1", locale: "en", singleton: true)
    assert_equal({"id" => "draft-1", "some_field" => "saved"}, payload)
    document = graphql.documents.first
    assert_includes document, "homepage(locale: $locale, fallbackLocales: [])"
    refute_includes document, "filter:"
    assert_equal({locale: "en"}, graphql.variables)

    mismatch = FakeGraphQL.new(Response.new({"homepage" => {"id" => "other"}}, Errors.new([])))
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      client(mismatch).fetch(model: "homepage", root: "homepage", fields: "id",
        cms_id: "draft-1", locale: "en", singleton: true)
    end
  end

  def test_fetch_maps_missing_errors_and_network_failures
    empty = FakeGraphQL.new(Response.new({"article" => nil}, Errors.new([])))
    assert_raises(ParademCmsSite::Preview::NotFound) do
      client(empty).fetch(model: "article", root: "article", fields: "id", cms_id: "draft-1", locale: "en")
    end

    errors = FakeGraphQL.new(Response.new({"article" => {"id" => "draft-1"}}, Errors.new([:boom])))
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      client(errors).fetch(model: "article", root: "article", fields: "id", cms_id: "draft-1", locale: "en")
    end

    mismatch = FakeGraphQL.new(Response.new({"article" => {"id" => "other"}}, Errors.new([])))
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      client(mismatch).fetch(model: "article", root: "article", fields: "id", cms_id: "draft-1", locale: "en")
    end

    network = Object.new
    def network.parse(document) = document
    def network.query(*) = raise(Timeout::Error)
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      client(network).fetch(model: "article", root: "article", fields: "id", cms_id: "draft-1", locale: "en")
    end
  end

  def test_fetch_rejects_records_outside_the_project_scope_before_network
    graphql = FakeGraphQL.new(Response.new({}, Errors.new([])))
    assert_raises(ParademCmsSite::Preview::NotFound) do
      client(graphql).fetch(model: "global", root: "global", fields: "id", cms_id: "draft-1", locale: "en")
    end
    assert_raises(ParademCmsSite::Preview::NotFound) do
      client(graphql).fetch(model: "article", root: "article", fields: "id", cms_id: "draft-1", locale: "de")
    end
    assert_empty graphql.documents
  end

  def test_client_refuses_unconfigured_or_invalid_environment
    @configuration.api_token = nil
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      ParademCmsSite::Preview::Client.new(configuration: @configuration, schema: nil, environment: "main-1")
    end
    @configuration.api_token = "draft-read-only-token"
    assert_raises(ParademCmsSite::Preview::Unavailable) do
      ParademCmsSite::Preview::Client.new(configuration: @configuration, schema: nil, environment: "../main")
    end
  end

  private

  def clone_configuration
    copy = ParademCmsSite::Preview::Configuration.new
    %i[enabled site_id secret api_token base_url models locales ttl verifier plugin_origin].each do |name|
      copy.public_send("#{name}=", @configuration.public_send(name))
    end
    copy.models = @configuration.models.dup
    copy.locales = @configuration.locales.dup
    copy
  end
end
