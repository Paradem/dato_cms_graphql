# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/rails_application"

class RailsInstallationTest < Minitest::Test
  include RailsApplicationFixture

  def test_fresh_rails_fixture_install_doctor_sync_webhook_and_host_callback
    with_application do |app, environment|
      arguments = %w[generate paradem_cms_site:install --site=fixture_site --fixture --locales=en,fr --models=Page,Global --singletons=Global --webhook=shared_header]
      rails(app, environment, *arguments)
      before = Dir[File.join(app, "db/migrate/*.rb")].to_h { |path| [path, File.binread(path)] }
      rails(app, environment, *arguments)
      assert_equal before, Dir[File.join(app, "db/migrate/*.rb")].to_h { |path| [path, File.binread(path)] }
      assert_equal 1, File.read(File.join(app, "config/routes.rb")).scan("paradem_cms_site/webhooks#create").length
      rails(app, environment, "db:migrate")
      output = rails(app, environment, "cms:doctor")
      assert_includes output, "OK fixture_site"
      refute_includes output, "sentinel-cms-token-not-live"
      script = File.join(app, "tmp/verify_installation.rb")
      File.write(script, <<~'RUBY')
        require "rack/mock"
        abort "Private gem installed" if Gem.loaded_specs.key?("paradem_cms_site")
        abort "Global client loaded" if DatoCmsGraphql.const_defined?(:Client, false)
        abort "Global loader loaded" if $LOADED_FEATURES.any? { |path| path.end_with?("/dato_cms_graphql.rb") }
        abort "Doctor populated content" unless CmsRecord.count.zero?
        ActiveJob::Base.queue_adapter = :test
        events = []
        ParademCmsSite.configure do |config|
          config.webhook_context = ->(_) { {"webhook_log_id" => 17} }
          config.after_sync = ->(result, context) { events << [result.site, result.record_count, context] }
        end
        request = Rack::MockRequest.new(Rails.application)
        unauthorized = request.post("/webhooks/dato", "HTTP_HOST" => "www.example.com")
        abort "Missing auth accepted" unless unauthorized.status == 401
        accepted = request.post("/webhooks/dato", "HTTP_HOST" => "www.example.com", "HTTP_WEBHOOK_AUTH" => ENV.fetch("DATO_WEBHOOK_SECRET"))
        abort "Webhook rejected" unless accepted.status == 200
        abort "Request performed sync inline" unless CmsRecord.count.zero?
        queued = ParademCmsSite::RefreshJob.queue_adapter.enqueued_jobs
        abort "Wrong job count" unless queued.length == 1
        ActiveJob::Base.execute(queued.first)
        abort "Wrong cache count" unless CmsRecord.count == 4
        abort "Wrong callback" unless events == [["fixture_site", 4, {"webhook_log_id" => 17}]]
        I18n.with_locale(:fr) do
          abort "Wrong localized content" unless Page.localized.first.title == "Synthetic Page (fr)"
          abort "Scoped singleton helper failed" unless GlobalQuery.get.title == "Synthetic Global (fr)"
          abort "Scoped collection helper failed" unless PageQuery.all.map(&:title) == ["Synthetic Page (fr)"]
          abort "Scoped iterator indexing failed" unless PageQuery.all[0].title == "Synthetic Page (fr)"
        end
        PageQuery.render(false)
        PageQuery.page_size(1)
        PageQuery.fallback_locale(:none)
        ParademCmsSite.configuration.installation.reload_queries!
        abort "Stale DSL defaults after full CLI reload" unless PageQuery.render? && PageQuery.graphql_page_size == 100 && PageQuery.fallback_locale_value.nil?
        I18n.with_locale(:en) { abort "Stale compiled query after reload" unless PageQuery.all[0].title == "Synthetic Page (en)" }
        abort "Scoped helpers loaded global boot" if DatoCmsGraphql.const_defined?(:Client, false)
        before = CmsRecord.order(:id).pluck(:cms_id, :locale, :cms_record)
        problems = ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems
        abort problems.join("\n") unless problems.empty?
        abort "Doctor changed cache" unless before == CmsRecord.order(:id).pluck(:cms_id, :locale, :cms_record)
        abort "Doctor ran host callback" unless events.length == 1
        ActiveJob::Base.queue_adapter = :inline
        abort "Inline queue not diagnosed" unless ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems.any? { |issue| issue.include?("ActiveJob queue") }
        ActiveJob::Base.queue_adapter = :test
        index = CmsRecord.connection.indexes(:cms_records).find { |entry| entry.unique && entry.columns == %w[type locale cms_id] }
        CmsRecord.connection.remove_index(:cms_records, name: index.name)
        abort "Missing identity index not diagnosed" unless ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems.any? { |issue| issue.include?("unique CMS identity") }
        CmsRecord.connection.add_index(:cms_records, [:type, :locale, :cms_id], unique: true)
        PageQuery.graphql_fields(:id, :nonexistent_field)
        abort "Invalid query not diagnosed" unless ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems.any? { |issue| issue.include?("query/schema") }
        PageQuery.graphql_fields(:id, :title, :permalink)
        class CapabilityProbeController < ApplicationController
          def index
            raise "Doctor must not dispatch route actions"
          end
        end
        Rails.application.routes.draw do
          post "webhooks/dato", to: "paradem_cms_site/webhooks#create"
          get "implemented", to: "capability_probe#index"
          get "missing-controller", to: "unimplemented#show"
          get "missing-action", to: "capability_probe#absent"
          get "duplicate-target", to: "capability_probe#absent"
          get "redirect", to: redirect("/implemented")
        end
        problems = ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems
        expected = ["Unimplemented route target: unimplemented#show", "Unimplemented route target: capability_probe#absent"]
        abort "Enabled capabilities not diagnosed: #{problems.inspect}" unless problems == expected
        abort "Route validation changed cache" unless before == CmsRecord.order(:id).pluck(:cms_id, :locale, :cms_record)
        Rails.application.routes.draw { post "webhooks/dato", to: "application#wrong" }
        abort "Wrong webhook route not diagnosed" unless ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems.any? { |issue| issue.include?("Webhook route") }
        puts "FRESH_APP_PASS"
      RUBY
      assert_includes rails(app, environment, "runner", script), "FRESH_APP_PASS"
      rails(app, environment, "cms:sync")
      assert_includes rails(app, environment, "cms:schema:snapshot", success: false), "disabled in CMS fixture mode"
      rails(app, environment, "cache_dato")
      rails(app, environment, "dato_cms:cache")
      assert_includes rails(app, environment, "queries:generate[Page]", success: false), "hand-authored queries"
      assert_includes rails(app, environment, "runner", 'abort unless CmsRecord.count == 4; puts "RAKE_SYNC_PASS"'), "RAKE_SYNC_PASS"
      production = rails(app, environment.merge("RAILS_ENV" => "production"), "runner", "puts :not_allowed", success: false)
      assert_includes production, "fixture mode is development/test only"
    end
  end

  def test_explicit_legacy_integer_caches_sync_and_pass_doctor_with_the_maintained_client
    [%w[en fr], %w[en]].each do |locales|
      with_application do |app, environment|
        rails(app, environment, "generate", "paradem_cms_site:install", "--site=legacy_cache", "--fixture", "--locales=#{locales.join(",")}")
        # Only this disposable fixture is converted. The installer is never an
        # updater for a real legacy model, schema or database.
        path = File.join(app, "config/cms_site.yml")
        manifest = YAML.safe_load_file(path)
        manifest["locale_storage"] = "integer"
        manifest["locale_mapping"] = locales.each_with_index.to_h
        File.write(path, YAML.dump(manifest))
        migration = Dir[File.join(app, "db/migrate/*.rb")].fetch(0)
        File.write(migration, File.read(migration).sub("t.string :locale", "t.integer :locale"))
        File.write(File.join(app, "app/models/cms_record.rb"), <<~RUBY)
          class CmsRecord < ApplicationRecord
            def self.dato_cms_locale_mapping
              #{manifest.fetch("locale_mapping").inspect}
            end
            include ParademCmsSite::CacheRecord
          end
        RUBY
        rails(app, environment, "db:migrate")
        assert_includes rails(app, environment, "cms:doctor"), "OK legacy_cache"
        rails(app, environment, "cms:sync")
        script = File.join(app, "tmp/verify_legacy.rb")
        File.write(script, <<~'RUBY')
          installation = ParademCmsSite.configuration.installation
          manifest = installation.manifest
          abort "Changed mapping" unless CmsRecord.locales == manifest.locale_mapping
          abort "Wrong row count" unless CmsRecord.count == manifest.locales.length
          expected = manifest.locales.map do |locale|
            I18n.with_locale(locale) do
              page = Page.localized.first!
              abort "Changed storage" unless page.locale_before_type_cast == manifest.locale_mapping.fetch(locale)
              abort "Changed JSON projection" unless page.title == "Synthetic Page (#{locale})"
              [locale, page.locale_before_type_cast]
            end
          end
          events = []
          ParademCmsSite.configure do |config|
            config.within_transaction = ->(_, context) do
              abort "Derived data ran outside transaction" unless CmsRecord.connection.transaction_open?
              events << [CmsRecord.order(:locale).map { |row| [row.locale, row.locale_before_type_cast] }, context]
            end
          end
          ParademCmsSite.refresh("synthetic-run" => 7)
          abort "Wrong derived-data locale projection" unless events == [[expected, {"synthetic-run" => 7}]]
          abort "Doctor rejected legacy cache" unless ParademCmsSite::RailsDoctor.new(installation).problems.empty?
          require "paradem_cms_site/published_client"
          ENV["DATO_API_INCLUDE_DRAFTS"] = "true"
          ENV["DATO_ENVIRONMENT"] = "synthetic-ambient"
          [nil, "synthetic-selected"].each do |selected|
            transport = DatoCmsGraphql::HTTPTransport.new(include_drafts: false, environment: selected)
            client = GraphQL::Client.new(schema: installation.client.schema, execute: transport)
            published = ParademCmsSite::PublishedClient.new(client: client, environment: selected)
            ENV["DATO_ENVIRONMENT"] = "synthetic-changed"
            headers = published.instance_variable_get(:@client).execute.headers(include_drafts: true)
            abort "Wrong environment snapshot" unless headers["X-Environment"] == selected
            abort "Drafts leaked" if headers.key?("X-Include-Drafts")
          end
          puts "LEGACY_CACHE_PASS"
        RUBY
        assert_includes rails(app, environment, "runner", script), "LEGACY_CACHE_PASS"
      end
    end
  end

  def test_live_setup_and_doctor_boot_without_network_schema_credentials_or_a_database
    with_application do |app, environment|
      args = %w[generate paradem_cms_site:install --site=live_example --webhook=disabled]
      rails(app, environment, *args, "--pretend")
      refute File.exist?(File.join(app, "config/cms_site.yml"))
      rails(app, environment, *args)
      missing_ui = rails(app, environment, "generate", "paradem_cms_site:resource", "Article", success: false)
      assert_includes missing_ui, "Add view_component"
      refute File.exist?(File.join(app, "app/models/article.rb"))
      manifest_path = File.join(app, "config/cms_site.yml")
      data = YAML.safe_load_file(manifest_path)
      data.fetch("rails")["allow_schema_introspection"] = true
      File.write(manifest_path, YAML.dump(data))
      output = rails(app, environment.merge("DATO_API_TOKEN" => nil), "cms:doctor", success: false)
      assert_includes output, "Supply the local GraphQL delivery schema"
      assert_includes output, "db:migrate"
      assert_includes output, "Configure DATO_API_TOKEN"
      assert_empty Dir[File.join(app, "storage/*.sqlite3")]
      refute File.exist?(File.join(app, "config/cms/schema.graphql"))
      refute_includes output, "sentinel-cms-token-not-live"
    end
  end
end
