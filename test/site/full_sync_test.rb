# frozen_string_literal: true

require_relative "test_helper"
require "paradem_cms_site/rails/installation"
require "paradem_cms_site/rails/full_sync"
require "stringio"

class FullSyncTest < Minitest::Test
  class Installation
    attr_reader :manifest, :events
    def initialize(manifest, events)
      @manifest, @events = manifest, events
    end

    def reload_queries! = events << :reload
    def reset_client! = events << :reset
  end

  def setup
    @previous = ParademCmsSite.configuration
    ParademCmsSite.instance_variable_set(:@configuration, ParademCmsSite::Configuration.new)
    @previous_token = ENV["DATO_API_TOKEN"]
    ENV["DATO_API_TOKEN"] = "synthetic-cli-token"
  end

  def teardown
    ParademCmsSite.instance_variable_set(:@configuration, @previous)
    ENV["DATO_API_TOKEN"] = @previous_token
  end

  def with_installation(generated: true)
    with_site(generated: generated, queries: ["Page"]) do |root, data|
      data["rails"] = {"cache_model" => "CmsRecord", "delivery_schema" => "config/delivery.json", "webhook" => "disabled"}
      manifest = ParademCmsSite::Manifest.new(data, root: root)
      events = []
      ParademCmsSite.configuration.sync = ->(context) { events << [:refresh, context] }
      installation = Installation.new(manifest, events)
      yield installation, events
    end
  end

  def with_snapshot(events)
    original = ParademCmsSite::SchemaSnapshot.method(:call)
    ParademCmsSite::SchemaSnapshot.define_singleton_method(:call) { |manifest|
      events << :snapshot
      manifest.path_for(:delivery_schema)
    }
    yield
  ensure
    ParademCmsSite::SchemaSnapshot.define_singleton_method(:call, original)
  end

  def runner(installation, events, fail_stage: nil)
    original_schema = File.read(installation.manifest.path_for(:schema_export)) if installation.manifest.generated_queries?
    lambda do |*arguments, chdir:|
      assert_equal installation.manifest.root.to_s, chdir
      stage = arguments.first.is_a?(Hash) ? :export : :format
      events << stage
      if stage == :export
        assert_equal({"DATOCMS_API_TOKEN" => "synthetic-cli-token"}, arguments.first)
        refute arguments.drop(1).any? { |argument| argument.include?("synthetic-cli-token") || argument.include?("--api-token") }
        File.write(arguments.fetch(4), original_schema)
      end
      stage != fail_stage
    end
  end

  def test_full_cli_exports_generates_formats_and_refreshes_in_order_without_token_argv_or_output
    with_installation do |installation, events|
      output = StringIO.new
      with_snapshot(events) do
        ParademCmsSite::FullSync.new(installation, command_runner: runner(installation, events), output: output).call
      end
      assert_equal [:export, :snapshot, :format, :reload, [:refresh, {"source" => "cli"}]], events
      assert_includes File.read(installation.manifest.query_file_for("Page")), "< ParademCmsSite::Query"
      refute_includes output.string, "synthetic-cli-token"
    end
  end

  def test_export_or_formatter_failure_never_refreshes_content
    [:export, :format].each do |failure|
      with_installation do |installation, events|
        before = File.read(installation.manifest.path_for(:schema_export))
        with_snapshot(events) do
          assert_raises(ParademCmsSite::FullSync::CommandError) do
            ParademCmsSite::FullSync.new(installation, command_runner: runner(installation, events, fail_stage: failure), output: StringIO.new).call
          end
        end
        refute events.any? { |event| event.is_a?(Array) && event.first == :refresh }
        assert_equal before, File.read(installation.manifest.path_for(:schema_export)) if failure == :export
      end
    end
  end

  def test_an_incomplete_export_does_not_replace_the_canonical_schema_or_refresh
    with_installation do |installation, events|
      before = File.read(installation.manifest.path_for(:schema_export))
      bad_runner = ->(*arguments, **) {
        File.write(arguments.fetch(4), "not a schema")
        true
      }
      assert_raises(KeyError) { ParademCmsSite::FullSync.new(installation, command_runner: bad_runner, output: StringIO.new).call }
      assert_empty events
      assert_equal before, File.read(installation.manifest.path_for(:schema_export))
    end
  end

  def test_hand_authored_queries_are_never_exported_regenerated_or_formatted
    with_installation(generated: false) do |installation, events|
      before = File.read(installation.manifest.query_file_for("Page"))
      with_snapshot(events) do
        ParademCmsSite::FullSync.new(installation, command_runner: ->(*) { flunk "Unexpected subprocess" }, output: StringIO.new).call
      end
      assert_equal [:snapshot, :reset, [:refresh, {"source" => "cli"}]], events
      assert_equal before, File.read(installation.manifest.query_file_for("Page"))
    end
  end

  def test_snapshot_environment_prefers_delivery_and_preserves_legacy_schema_environment
    with_installation do |installation, _events|
      manifest = installation.manifest
      original = GraphQL::Client.method(:dump_schema)
      seen = []
      GraphQL::Client.define_singleton_method(:dump_schema) do |transport|
        seen << transport.headers(include_drafts: false)["X-Environment"]
        original.call(GraphQL::Schema.from_definition("type Query { synthetic: String }"))
      end
      previous = ENV.values_at("DATO_ENVIRONMENT", "DATO_SCHEMA_ENVIRONMENT")
      ENV["DATO_ENVIRONMENT"] = nil
      ENV["DATO_SCHEMA_ENVIRONMENT"] = "synthetic-schema-only"
      ParademCmsSite::SchemaSnapshot.call(manifest)
      ENV["DATO_ENVIRONMENT"] = "synthetic-delivery"
      ParademCmsSite::SchemaSnapshot.call(manifest)
      assert_equal ["synthetic-schema-only", "synthetic-delivery"], seen
    ensure
      ENV["DATO_ENVIRONMENT"], ENV["DATO_SCHEMA_ENVIRONMENT"] = previous
      GraphQL::Client.define_singleton_method(:dump_schema, original)
    end
  end

  def test_snapshot_uses_published_selected_headers_and_keeps_the_last_good_file_on_failure
    with_installation do |installation, _events|
      manifest = installation.manifest
      path = manifest.path_for(:delivery_schema)
      File.write(path, "last-good")
      original = GraphQL::Client.method(:dump_schema)
      seen = nil
      GraphQL::Client.define_singleton_method(:dump_schema) do |transport|
        seen = transport.headers(include_drafts: true)
        raise IOError, "synthetic metadata failure"
      end
      assert_raises(IOError) { ParademCmsSite::SchemaSnapshot.call(manifest, environment: "synthetic-selected") }
      assert_equal "last-good", File.read(path)
      assert_equal "synthetic-selected", seen.fetch("X-Environment")
      refute seen.key?("X-Include-Drafts")
    ensure
      GraphQL::Client.define_singleton_method(:dump_schema, original)
    end
  end
end
