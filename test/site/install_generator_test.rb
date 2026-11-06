# frozen_string_literal: true

require_relative "test_helper"
require "rails/generators"
require "generators/paradem_cms_site/install/install_generator"
require "paradem_cms_site/rails/installation"

class InstallGeneratorTest < Minitest::Test
  def with_app
    Dir.mktmpdir("cms-install-test-") do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      yield root
    end
  end

  def install(root, **options)
    generator = ParademCmsSite::Generators::InstallGenerator.new([], {site: "fixture", fixture: true}.merge(options), destination_root: root)
    capture_io { generator.install }
  end

  def snapshot(root)
    Dir[File.join(root, "**/*"), File.join(root, ".*/*")].select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
  end

  def test_fixture_installation_is_repeatable_and_contains_no_copied_runtime_services
    with_app do |root|
      install(root, locales: "en,fr", models: "Page,Global", singletons: "Global", webhook: "hmac_sha256")
      first = snapshot(root)
      install(root, locales: "en,fr", models: "Page,Global", singletons: "Global", webhook: "hmac_sha256")
      assert_equal first, snapshot(root)
      manifest = ParademCmsSite::Manifest.load(root: root)
      assert_equal %w[en fr], manifest.locales
      assert_equal "hmac_sha256", manifest.data.fetch("rails").fetch("webhook")
      assert_equal 1, Dir[File.join(root, "db/migrate/*_create_cms_records.rb")].length
      assert_equal 1, File.read(File.join(root, "config/routes.rb")).scan("paradem_cms_site/webhooks#create").length
      assert_empty Dir[File.join(root, "app/{services,jobs,controllers}/**/*")]
      refute File.exist?(File.join(root, ".github"))
      refute File.exist?(File.join(root, "bin"))
      assert_empty ParademCmsSite::Doctor.new(manifest).problems
    end
  end

  def test_application_file_conflicts_are_found_before_any_write_even_with_force
    with_app do |root|
      FileUtils.mkdir_p(File.join(root, "app/models"))
      File.write(File.join(root, "app/models/page.rb"), "# Host-owned model\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { install(root, force: true) }
      assert_equal before, snapshot(root)
    end
  end

  def test_existing_webhook_route_is_not_shadowed
    with_app do |root|
      File.write(File.join(root, "config/routes.rb"), "Rails.application.routes.draw do\n  post \"webhooks/dato\", to: \"existing#create\"\nend\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { install(root) }
      assert_equal before, snapshot(root)
    end
  end

  def test_pretend_writes_nothing_and_disabled_webhooks_add_no_route
    with_app do |root|
      before = snapshot(root)
      install(root, pretend: true)
      assert_equal before, snapshot(root)
      install(root, webhook: "disabled")
      assert_equal before.fetch(File.join(root, "config/routes.rb")), File.read(File.join(root, "config/routes.rb"))
    end
  end

  def test_symlinked_destinations_cannot_write_outside_the_application
    with_app do |root|
      Dir.mktmpdir("cms-install-outside-") do |outside|
        File.symlink(outside, File.join(root, "app"))
        assert_raises(Rails::Generators::Error) { install(root) }
        assert_empty Dir.children(outside)
      end
    end
  end

  def test_invalid_options_do_not_partially_install
    with_app do |root|
      before = snapshot(root)
      [{site: "bad/site"}, {models: "Page,Page"}, {models: "../Page"}, {models: "FAQ"}, {models: "Object"}, {locales: "en,en"}, {locales: "en-US"},
        {singletons: "Other"}, {cache_model: "Page"}, {cache_model: "SchemaMigration"}, {webhook: "automatic"}].each do |options|
        assert_raises(Rails::Generators::Error) { install(root, **options) }
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_fixture_client_executes_real_graphql_without_api_credentials
    with_app do |root|
      install(root, locales: "en,fr", models: "Page,Global", singletons: "Global")
      manifest = ParademCmsSite::Manifest.load(root: root)
      client = ParademCmsSite::ClientFactory.new(manifest).call
      result = client.execute.execute("{ allPages(locale: fr) { id title permalink } global(locale: en) { id } _allPagesMeta { count } }")
      assert_empty result.to_h.fetch("errors", [])
      assert_equal "fixture-page-fr", result.to_h.dig("data", "allPages", 0, "id")
      assert_equal "fixture-global-en", result.to_h.dig("data", "global", "id")
      assert_equal 1, result.to_h.dig("data", "_allPagesMeta", "count")
      refute DatoCmsGraphql.const_defined?(:Client, false)
      refute $LOADED_FEATURES.any? { |path| path.end_with?("/dato_cms_graphql.rb") }
    end
  end

  def test_singleton_whose_name_begins_with_all_is_not_treated_as_a_collection
    with_app do |root|
      install(root, models: "All", singletons: "All")
      client = ParademCmsSite::ClientFactory.new(ParademCmsSite::Manifest.load(root: root)).call
      result = client.execute.execute("{ all(locale: en) { id } }")
      assert_empty result.to_h.fetch("errors", [])
      assert_equal "fixture-all-en", result.to_h.dig("data", "all", "id")
    end
  end

  def test_local_sdl_and_introspection_json_build_a_live_transport_without_loading_global_client_or_credentials
    with_app do |root|
      install(root)
      data = YAML.safe_load_file(File.join(root, "config/cms_site.yml"))
      data.fetch("rails").delete("fixture_data")
      manifest = ParademCmsSite::Manifest.new(data, root: root)
      old = ENV.delete("DATO_API_TOKEN")
      begin
        client = ParademCmsSite::ClientFactory.new(manifest).call
        assert_instance_of DatoCmsGraphql::HTTPTransport, client.execute
        assert client.parse("query { allPages(locale: en) { id } }")
        json = "config/cms/schema.json"
        File.write(File.join(root, json), JSON.generate(client.schema.as_json))
        data.fetch("rails")["delivery_schema"] = json
        second = ParademCmsSite::ClientFactory.new(ParademCmsSite::Manifest.new(data, root: root)).call
        assert_instance_of DatoCmsGraphql::HTTPTransport, second.execute
        assert second.parse("query { allPages(locale: en) { title } }")
        refute DatoCmsGraphql.const_defined?(:Client, false)
      ensure
        ENV["DATO_API_TOKEN"] = old
      end
    end
  end

  def test_production_install_does_not_create_or_fetch_a_fake_schema
    with_app do |root|
      install(root, fixture: false)
      manifest = ParademCmsSite::Manifest.load(root: root)
      refute manifest.path_for(:delivery_schema).exist?
      assert_nil manifest.path_for(:fixture_data)
      assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::ClientFactory.new(manifest).call }
    end
  end
end
