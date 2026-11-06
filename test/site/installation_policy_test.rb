# frozen_string_literal: true

require_relative "test_helper"
require "rails"
require "paradem_cms_site/rails/installation"

class InstallationPolicyTest < Minitest::Test
  def setup
    @previous = ParademCmsSite.configuration
    ParademCmsSite.instance_variable_set(:@configuration, ParademCmsSite::Configuration.new)
    @logger = ::Rails.logger
    ::Rails.logger = Logger.new(StringIO.new)
  end

  def teardown
    ParademCmsSite.instance_variable_set(:@configuration, @previous)
    ::Rails.logger = @logger
  end

  def with_installation(fallback: false, cache: true)
    with_site(generated: false) do |root, data|
      data["rails"] = {"cache_model" => "CmsRecord", "delivery_schema" => "config/missing.json", "webhook" => "disabled",
                       "allow_schema_introspection" => true, "boot_fallback" => fallback}
      File.write(File.join(root, "config/cms_site.yml"), YAML.dump(data))
      installation = ParademCmsSite::Installation.new(root: root)
      record = Object.new
      record.define_singleton_method(:exists?) { cache }
      installation.define_singleton_method(:record_class) { record }
      yield installation
    end
  end

  def test_boot_is_strict_by_default_even_with_an_existing_cache
    with_installation do |installation|
      ParademCmsSite.configuration.sync = ->(context) {
        assert_equal({"source" => "boot"}, context)
        raise IOError, "offline"
      }
      assert_raises(IOError) { installation.boot! }
    end
  end

  def test_opted_in_warm_boot_retains_cache_and_queues_a_standard_retry
    with_installation(fallback: true) do |installation|
      ParademCmsSite.configuration.sync = ->(_) { raise ParademCmsSite::Sync::FetchError, "synthetic failure" }
      original = ParademCmsSite::RefreshJob.method(:perform_later)
      contexts = []
      ParademCmsSite::RefreshJob.define_singleton_method(:perform_later) { |context| contexts << context }
      installation.boot!
      assert_equal [{"source" => "boot_retry"}], contexts
    ensure
      ParademCmsSite::RefreshJob.define_singleton_method(:perform_later, original)
    end
  end

  def test_cold_boot_or_a_persistence_error_never_uses_the_warm_cache_fallback
    with_installation(fallback: true, cache: false) do |installation|
      ParademCmsSite.configuration.sync = ->(_) { raise IOError, "offline" }
      assert_raises(IOError) { installation.boot! }
    end
    with_installation(fallback: true) do |installation|
      ParademCmsSite.configuration.sync = ->(_) { raise ActiveRecord::StatementInvalid, "synthetic persistence failure" }
      assert_raises(ActiveRecord::StatementInvalid) { installation.boot! }
    end
  end

  def test_introspection_requires_explicit_runtime_opt_in_and_is_never_an_offline_factory_fallback
    with_installation do |installation|
      original = GraphQL::Client.method(:load_schema)
      calls = []
      GraphQL::Client.define_singleton_method(:load_schema) do |source|
        calls << source if source.is_a?(GraphQL::Client::HTTP)
        GraphQL::Schema.from_definition("type Query { synthetic: String }")
      end
      assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::ClientFactory.new(installation.manifest).call }
      assert_empty calls
      client = ParademCmsSite::ClientFactory.new(installation.manifest, allow_schema_introspection: true).call
      assert_instance_of GraphQL::Client, client
      assert_equal 1, calls.length
      assert_instance_of DatoCmsGraphql::HTTPTransport, calls.first
      refute File.exist?(installation.manifest.path_for(:delivery_schema))
    ensure
      GraphQL::Client.define_singleton_method(:load_schema, original)
    end
  end
end
