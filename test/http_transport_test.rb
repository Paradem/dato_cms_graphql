# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

class HTTPTransportTest < Minitest::Test
  ENVIRONMENT_KEYS = %w[DATO_API_TOKEN DATO_API_INCLUDE_DRAFTS DATO_ENVIRONMENT PROJECT].freeze

  def setup
    @previous = ENVIRONMENT_KEYS.to_h { |name| [name, ENV[name]] }
    ENVIRONMENT_KEYS.each { |name| ENV.delete(name) }
    ENV["DATO_API_TOKEN"] = "synthetic-offline-token"
    ENV["PROJECT"] = "synthetic-project"
    @transport = DatoCmsGraphql::HTTPTransport.new
  end

  def teardown
    @previous.each { |name, value| ENV[name] = value }
  end

  def test_published_requests_omit_drafts_for_every_legacy_preview_setting
    [nil, "", "false", "true"].each do |setting|
      ENV["DATO_API_INCLUDE_DRAFTS"] = setting
      refute @transport.headers(include_drafts: false).key?("X-Include-Drafts")
    end
  end

  def test_only_explicit_boolean_true_enables_context_drafts
    ENV["DATO_API_INCLUDE_DRAFTS"] = "true"
    [false, nil, "false", "true", 0].each do |value|
      refute @transport.headers(include_drafts: value).key?("X-Include-Drafts")
    end
    ENV["DATO_API_INCLUDE_DRAFTS"] = "false"
    assert_equal "true", @transport.headers(include_drafts: true)["X-Include-Drafts"]
  end

  def test_legacy_default_requires_the_exact_true_environment_value
    [nil, "", "false", "TRUE"].each do |setting|
      ENV["DATO_API_INCLUDE_DRAFTS"] = setting
      refute @transport.headers({}).key?("X-Include-Drafts")
    end
    ENV["DATO_API_INCLUDE_DRAFTS"] = "true"
    assert_equal "true", @transport.headers(nil)["X-Include-Drafts"]
  end

  def test_headers_include_authorization_json_and_editing_context
    headers = @transport.headers({})
    assert_equal "synthetic-offline-token", headers["Authorization"]
    assert_equal "application/json", headers["Accept"]
    assert_equal "application/json", headers["Content-Type"]
    assert_equal "https://synthetic-project.admin.datocms.com", headers["X-Base-Editing-Url"]
  end

  def test_environment_is_explicit_and_blank_values_are_omitted
    [nil, "", " "].each do |environment|
      ENV["DATO_ENVIRONMENT"] = environment
      refute @transport.headers({}).key?("X-Environment")
    end
    ENV["DATO_ENVIRONMENT"] = "synthetic-sandbox"
    assert_equal "synthetic-sandbox", @transport.headers(include_drafts: false)["X-Environment"]
  end

  def test_context_and_previous_header_hashes_are_not_mutated_or_reused
    context = {include_drafts: false}.freeze
    first = @transport.headers(context)
    first["X-Include-Drafts"] = "true"
    refute @transport.headers(context).key?("X-Include-Drafts")
    assert_equal({include_drafts: false}, context)
  end

  def test_constructing_transport_needs_no_token_but_reading_headers_does
    ENV.delete("DATO_API_TOKEN")
    transport = DatoCmsGraphql::HTTPTransport.new
    assert_instance_of DatoCmsGraphql::HTTPTransport, transport
    assert_raises(KeyError) { transport.headers(include_drafts: false) }
  end

  def test_transport_is_independently_loadable_without_boot_or_networking
    result = isolated(<<~RUBY)
      require "dato_cms_graphql/http_transport"
      transport = DatoCmsGraphql::HTTPTransport.new
      puts JSON.generate(
        transport: transport.class.name,
        main_loaded: $LOADED_FEATURES.any? { |path| path.end_with?("/dato_cms_graphql.rb") },
        rails_loaded: defined?(Rails::Application) ? true : false,
        test_schema_loaded: defined?(TestSchema) ? true : false
      )
    RUBY
    assert_equal "DatoCmsGraphql::HTTPTransport", result.fetch("transport")
    refute result.fetch("main_loaded")
    refute result.fetch("rails_loaded")
    refute result.fetch("test_schema_loaded")
  end

  def test_default_client_uses_the_same_transport_for_schema_and_delivery
    result = isolated(<<~RUBY, "DATO_API_TOKEN" => "synthetic-offline-token", "DATO_ENVIRONMENT" => "synthetic-sandbox", "DATO_API_INCLUDE_DRAFTS" => "false")
      require "graphql/client"
      require "graphql/client/http"
      original = GraphQL::Client.method(:load_schema)
      seen = []
      GraphQL::Client.define_singleton_method(:load_schema) do |source|
        if source.is_a?(GraphQL::Client::HTTP)
          seen << source
          TestSchema
        else
          original.call(source)
        end
      end
      require "dato_cms_graphql"
      puts JSON.generate(
        transport: DatoCmsGraphql::HTTP.class.name,
        schema_loads: seen.length,
        same_transport: seen.first.equal?(DatoCmsGraphql::HTTP),
        same_delivery: DatoCmsGraphql::Client.instance_variable_get(:@execute).equal?(DatoCmsGraphql::HTTP),
        environment: seen.first.headers({})["X-Environment"],
        draft_header: seen.first.headers({}).key?("X-Include-Drafts")
      )
    RUBY
    assert_equal "DatoCmsGraphql::HTTPTransport", result.fetch("transport")
    assert_equal 1, result.fetch("schema_loads")
    assert result.fetch("same_transport")
    assert result.fetch("same_delivery")
    assert_equal "synthetic-sandbox", result.fetch("environment")
    refute result.fetch("draft_header")
  end

  private

  def isolated(script, overrides = {})
    root = File.expand_path("..", __dir__)
    environment = %w[PATH HOME GEM_HOME GEM_PATH BUNDLE_GEMFILE].to_h { |name| [name, ENV[name]] }
    # A real request is a test failure, not a way to obtain a schema/fixture.
    guard = <<~RUBY
      require "json"
      require "net/http"
      Net::HTTP.prepend(Module.new do
        def request(*)
          raise "Network is forbidden in transport tests"
        end
      end)
    RUBY
    stdout, stderr, status = Open3.capture3(environment.merge(overrides), RbConfig.ruby,
      "-rbundler/setup", "-I#{File.join(root, "lib")}", "-e", guard + script,
      chdir: root, unsetenv_others: true)
    assert status.success?, stderr
    JSON.parse(stdout)
  end
end
