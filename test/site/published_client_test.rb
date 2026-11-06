# frozen_string_literal: true

require_relative "test_helper"
require "paradem_cms_site/published_client"
require "paradem_cms_site/sync"
require "net/http"

class PublishedClientTest < Minitest::Test
  class QueryType < GraphQL::Schema::Object
    field :greeting, String, null: false
  end

  class Schema < GraphQL::Schema
    query QueryType
  end

  Parser = GraphQL::Client.new(schema: Schema)
  Operation = Parser.parse("query { greeting }")

  class Transport < GraphQL::Client::HTTP
    attr_accessor :values
    attr_reader :requests, :contexts

    def initialize(values = {})
      super("https://cms.invalid/graphql")
      @values = {"Authorization" => +"synthetic-read-token"}.merge(values)
      @requests = []
      @contexts = []
    end

    def headers(context)
      @contexts << context
      values
    end

    def connection
      self
    end

    def request(request)
      requests << request
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate("data" => {"greeting" => "synthetic"})
      response
    end
  end

  def test_uses_existing_schema_and_connection_but_snapshots_published_headers
    source = Transport.new("X-Environment" => "fixture-environment")
    original = GraphQL::Client.new(schema: Schema, execute: source)
    published = ParademCmsSite::PublishedClient.new(client: original, environment: "fixture-environment")
    source.values["Authorization"].replace("changed-after-construction")
    source.values["X-Environment"] = "wrong-environment"
    source.values["X-Include-Drafts"] = "true"
    response = published.query(Operation, context: {include_drafts: true})
    assert_equal "synthetic", response.data.greeting
    request = source.requests.fetch(0)
    assert_equal "synthetic-read-token", request["Authorization"]
    assert_equal "fixture-environment", request["X-Environment"]
    refute request.key?("X-Include-Drafts")
    assert_equal [{include_drafts: false}], source.contexts
    assert_same source, original.execute
    assert_equal "true", source.values["X-Include-Drafts"]
  end

  def test_rejects_every_draft_header_including_legacy_false_values
    [true, false, "false", "true", "", nil].each do |value|
      source = Transport.new("x-include-drafts" => value)
      client = GraphQL::Client.new(schema: Schema, execute: source)
      error = assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::PublishedClient.new(client: client, environment: nil)
      end
      assert_includes error.message, "draft"
      assert_empty source.requests
    end
  end

  def test_environment_must_match_the_transport_including_primary_selection
    [[{}, "fixture"], [{"X-Environment" => "fixture"}, nil], [{"X-Environment" => "other"}, "fixture"], [{"X-Environment" => ""}, nil]].each do |headers, expected|
      source = Transport.new(headers)
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::PublishedClient.new(client: GraphQL::Client.new(schema: Schema, execute: source), environment: expected)
      end
      assert_empty source.requests
    end
  end

  def test_primary_environment_omits_environment_and_draft_headers
    source = Transport.new
    published = ParademCmsSite::PublishedClient.new(client: GraphQL::Client.new(schema: Schema, execute: source), environment: " ")
    published.query(Operation)
    refute source.requests.first.key?("X-Environment")
    refute source.requests.first.key?("X-Include-Drafts")
  end

  def test_endpoint_changes_are_rejected_before_a_request
    source = Transport.new
    published = ParademCmsSite::PublishedClient.new(client: GraphQL::Client.new(schema: Schema, execute: source), environment: nil)
    source.uri.host = "different.invalid"
    assert_raises(ParademCmsSite::ConfigurationError) { published.query(Operation) }
    assert_empty source.requests
  end

  def test_sync_automatically_checks_real_graphql_http_clients_before_fetching
    with_site(generated: false) do |root, data|
      source = Transport.new("X-Include-Drafts" => false)
      error = assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::Sync.new(manifest: ParademCmsSite::Manifest.new(data, root: root), queries: [],
          client: GraphQL::Client.new(schema: Schema, execute: source), record_class: nil)
      end
      assert_includes error.message, "draft"
      assert_empty source.requests
    end
  end
end
