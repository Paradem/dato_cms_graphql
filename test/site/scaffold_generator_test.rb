# frozen_string_literal: true

require_relative "test_helper"
require "generators/paradem_cms_site/install/install_generator"
require "generators/paradem_cms_site/resource/resource_generator"
require "generators/paradem_cms_site/block/block_generator"
require "generators/paradem_cms_site/theme/theme_generator"
require "paradem_cms_site/rails/client_factory"
require "ripper"

class ScaffoldGeneratorTest < Minitest::Test
  GENERATORS = {resource: ParademCmsSite::Generators::ResourceGenerator, block: ParademCmsSite::Generators::BlockGenerator, theme: ParademCmsSite::Generators::ThemeGenerator}.freeze

  def with_app
    Dir.mktmpdir("cms-scaffold-") do |root|
      %w[config app/assets/tailwind].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
      File.write(File.join(root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      File.write(File.join(root, "config/importmap.rb"), "# Host-owned pins\npin \"application\"\n")
      File.write(File.join(root, "app/assets/tailwind/application.css"), "@import \"tailwindcss\";\n")
      capture_io { ParademCmsSite::Generators::InstallGenerator.new([], {site: "starter", fixture: true, locales: "en,fr", models: "Page,Global", singletons: "Global"}, destination_root: root).install }
      yield root
    end
  end

  def generate(kind, root, name, **options)
    generator = GENERATORS.fetch(kind).new([name], options, destination_root: root)
    capture_io { generator.public_send("generate_#{kind}") }
  end

  def snapshot(root)
    Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix("#{root}/"), File.binread(path)] }
  end

  def test_resource_extends_only_managed_synthetic_inputs_and_reruns_identically
    with_app do |root|
      generate(:resource, root, "Article", body: "body", permalink: "slug", fallback_locale: "none")
      manifest = ParademCmsSite::Manifest.load(root: root)
      assert_equal %w[Page Global Article], manifest.queries
      assert_equal "slug", manifest.data.fetch("permalink_fields").fetch("Article")
      client = ParademCmsSite::ClientFactory.new(manifest).call
      result = client.execute.execute("{ allArticles(locale: fr) { id title slug body } }").to_h
      assert_empty result.fetch("errors", [])
      assert_equal "fixture-article-fr", result.dig("data", "allArticles", 0, "id")
      assert_equal "fr-article", result.dig("data", "allArticles", 0, "slug")
      assert_equal "Synthetic plain-text body.", result.dig("data", "allArticles", 0, "body")
      source = File.read(File.join(root, "app/queries/article_query.rb"))
      assert_operator source.index("fallback_locale :none"), :<, source.index("graphql_fields")
      before = snapshot(root)
      generate(:resource, root, "Article", body: "body", permalink: "slug", fallback_locale: "none")
      assert_equal before, snapshot(root)
      assert_equal 1, Dir[File.join(root, "db/migrate/*.rb")].length
      assert_equal 1, File.read(File.join(root, "config/routes.rb")).scan("as: :cms_article").length
      assert_empty ParademCmsSite::Doctor.new(manifest).problems
      state = JSON.parse(File.read(File.join(root, ParademCmsSite::Generators::Base::STATE_PATH)))
      assert_equal ParademCmsSite::VERSION, state.fetch("generators").fetch("resource:Article").fetch("version")
      assert_empty snapshot(root).keys.grep(/sqlite|\.env|\.key|dump|app\/(services|jobs)\//)
    end
  end

  def test_owned_installer_model_can_gain_presentation_without_changing_query_or_fixture
    with_app do |root|
      before = snapshot(root)
      generate(:resource, root, "Page")
      %w[app/models/page.rb app/queries/page_query.rb config/cms/schema.graphql config/cms/fixture.json config/cms_site.yml].each do |path|
        assert_equal before.fetch(path), File.binread(File.join(root, path))
      end
      assert File.file?(File.join(root, "test/integration/cms_page_test.rb"))
    end
  end

  def test_singleton_has_a_locale_route_and_real_fixture_query
    with_app do |root|
      generate(:resource, root, "Home", singleton: true, fallback_locale: "none")
      assert_includes File.read(File.join(root, "config/routes.rb")), 'get "cms/:locale/homes", to: "site/homes#show", as: :cms_home'
      refute_includes File.read(File.join(root, "app/controllers/site/homes_controller.rb")), "params[:permalink]"
      client = ParademCmsSite::ClientFactory.new(ParademCmsSite::Manifest.load(root: root)).call
      assert_equal "fixture-home-fr", client.execute.execute("{ home(locale: fr) { id } }").to_h.dig("data", "home", "id")
    end
  end

  def test_all_generators_pretend_without_writes
    with_app do |root|
      before = snapshot(root)
      [[:resource, "Article"], [:block, "promo"], [:theme, "journal"]].each do |kind, name|
        generate(kind, root, name, pretend: true)
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_late_host_file_conflict_prevents_manifest_schema_routes_and_all_other_writes
    with_app do |root|
      path = File.join(root, "test/components/site/article_component_test.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "# Host-owned sentinel\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article", force: true) }
      assert_equal before, snapshot(root)
    end
  end

  def test_customized_shared_inputs_cannot_be_silently_merged
    %w[config/cms_site.yml config/cms/schema.graphql config/cms/fixture.json].each do |relative|
      with_app do |root|
        File.open(File.join(root, relative), "a") { |file| file.write("\n") }
        before = snapshot(root)
        assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article", force: true) }
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_theme_preserves_importmap_and_wires_css_and_real_routes_once
    with_app do |root|
      pins = File.binread(File.join(root, "config/importmap.rb"))
      generate(:theme, root, "journal")
      before = snapshot(root)
      generate(:theme, root, "journal")
      assert_equal before, snapshot(root)
      assert_equal pins, File.binread(File.join(root, "config/importmap.rb"))
      css = File.read(File.join(root, "app/assets/tailwind/application.css"))
      assert_equal 1, css.scan('@import "./themes/journal.css";').length
      assert_equal 1, css.scan('@source "../../components";').length
      assert_equal 1, File.read(File.join(root, "config/routes.rb")).scan("as: :cms_journal_theme").length
      assert_includes File.read(File.join(root, "app/views/layouts/site/journal.html.erb")), "javascript_importmap_tags"
      workflow = YAML.safe_load_file(File.join(root, ".github/workflows/cms-fixtures.yml"))
      assert_equal "test", workflow.fetch("jobs").fetch("fixtures").fetch("env").fetch("RAILS_ENV")
      generate(:resource, root, "Article", theme: "journal")
      assert_includes File.read(File.join(root, "app/controllers/site/articles_controller.rb")), 'layout "site/journal"'
    end
  end

  def test_multiple_theme_imports_do_not_duplicate_component_sources_or_change_existing_theme
    with_app do |root|
      generate(:theme, root, "journal")
      first = File.binread(File.join(root, "app/assets/tailwind/themes/journal.css"))
      generate(:theme, root, "folio")
      assert_equal first, File.binread(File.join(root, "app/assets/tailwind/themes/journal.css"))
      assert_equal 1, File.read(File.join(root, "app/assets/tailwind/application.css")).scan('@source "../../components";').length
      generate(:theme, root, "journal")
    end
  end

  def test_block_is_site_owned_without_a_registry_query_or_cms_mutation
    with_app do |root|
      before = snapshot(root)
      generate(:block, root, "promo", layout: "section")
      %w[config/cms_site.yml config/cms/schema.graphql config/cms/fixture.json config/routes.rb].each { |path| assert_equal before.fetch(path), File.binread(File.join(root, path)) }
      template = File.read(File.join(root, "app/components/site/blocks/promo.html.erb"))
      assert_includes template, 'class="w-full px-6 py-12"'
      refute_includes template, "html_safe"
      assert_empty Dir[File.join(root, "app/queries/*promo*"), File.join(root, "*migrations*/*promo*")]
      generated = snapshot(root)
      generate(:block, root, "promo", layout: "section")
      assert_equal generated, snapshot(root)
    end
  end

  def test_existing_erb_convention_is_reused_and_ambiguous_templates_fail
    with_app do |root|
      generate(:block, root, "promo")
      html = File.join(root, "app/components/site/blocks/promo.html.erb")
      erb = File.join(root, "app/components/site/blocks/promo.erb")
      File.rename(html, erb)
      generate(:block, root, "promo")
      refute File.exist?(html)
      FileUtils.cp(erb, html)
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:block, root, "promo") }
      assert_equal before, snapshot(root)
    end
  end

  def test_removed_or_untracked_routes_and_removed_asset_wiring_are_not_reenabled
    with_app do |root|
      generate(:resource, root, "Article")
      route_path = File.join(root, "config/routes.rb")
      File.write(route_path, File.read(route_path).lines.reject { |line| line.include?("as: :cms_article") }.join)
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article", force: true) }
      assert_equal before, snapshot(root)
    end
    with_app do |root|
      File.write(File.join(root, "config/routes.rb"), "Rails.application.routes.draw do\n  get \"cms/:locale/articles/:permalink\", to: \"site/articles#show\", as: :cms_article\nend\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article") }
      assert_equal before, snapshot(root)
    end
    with_app do |root|
      generate(:theme, root, "journal")
      css_path = File.join(root, "app/assets/tailwind/application.css")
      File.write(css_path, File.read(css_path).lines.reject { |line| line.include?("./themes/journal.css") }.join)
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:theme, root, "journal", force: true) }
      assert_equal before, snapshot(root)
    end
  end

  def test_changed_options_and_force_do_not_become_an_updater
    with_app do |root|
      generate(:block, root, "promo")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:block, root, "promo", layout: "wide", force: true) }
      assert_equal before, snapshot(root)
    end
  end

  def test_symlinked_outputs_and_metadata_cannot_escape
    with_app do |root|
      Dir.mktmpdir("cms-scaffold-outside-") do |outside|
        File.symlink(outside, File.join(root, "app/components"))
        before = snapshot(root)
        assert_raises(Rails::Generators::Error) { generate(:block, root, "promo") }
        assert_equal before, snapshot(root)
        assert_empty Dir.children(outside)
        File.unlink(File.join(root, "app/components"))
        metadata = File.join(root, ParademCmsSite::Generators::Base::STATE_PATH)
        File.unlink(metadata)
        File.symlink(File.join(outside, "missing.json"), metadata)
        assert_raises(Rails::Generators::Error) { generate(:theme, root, "journal") }
        assert_empty Dir.children(outside)
      end
    end
  end

  def test_invalid_names_fields_routes_and_dependencies_fail_before_writes
    with_app do |root|
      before = snapshot(root)
      [[:resource, "Object", {}], [:resource, "FAQ", {}], [:resource, "Article", {body: "id"}], [:resource, "Article", {permalink: "title"}],
        [:resource, "Article", {body: "title); system('bad')"}], [:resource, "Article", {fallback_locale: "de"}], [:resource, "Article", {theme: "../outside"}],
        [:theme, "../outside", {}], [:block, "Bad::Constant", {}], [:block, "promo", {layout: "automatic"}]].each do |kind, name, options|
        assert_raises(Rails::Generators::Error) { generate(kind, root, name, **options) }
        assert_equal before, snapshot(root)
      end
      File.write(File.join(root, "config/routes.rb"), "Rails.application.routes.draw do\n  get \"cms/:locale/articles/:permalink\", to: \"existing#show\"\nend\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article") }
      assert_equal before, snapshot(root)
      File.unlink(File.join(root, "config/importmap.rb"))
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:theme, root, "journal") }
      assert_equal before, snapshot(root)
    end
  end

  def configure_generated_site(root, overrides)
    path = File.join(root, "config/cms_site.yml")
    data = YAML.safe_load_file(path)
    data.merge!("generated_queries" => true, "schema_export" => "config/cms/models.ts", "overrides_path" => "app/queries/overrides.yml")
    File.write(path, YAML.dump(data))
    File.write(File.join(root, data.fetch("schema_export")), "export type Article = ItemTypeDefinition<Settings, 'synthetic', { title: { type: 'string'; }; permalink: { type: 'slug'; }; }>;\n")
    File.write(File.join(root, data.fetch("overrides_path")), YAML.dump(overrides))
    metadata = File.join(root, ParademCmsSite::Generators::Base::STATE_PATH)
    state = JSON.parse(File.read(metadata))
    state.fetch("managed_files")["config/cms_site.yml"] = Digest::SHA256.file(path).hexdigest
    File.write(metadata, JSON.pretty_generate(state) + "\n")
  end

  def test_generated_queries_use_the_maintained_generator_and_strict_existing_overrides
    with_app do |root|
      configure_generated_site(root, {"Article" => {"single_instance" => true, "fallback_locale" => ":none"}})
      overrides = File.binread(File.join(root, "app/queries/overrides.yml"))
      generate(:resource, root, "Article", singleton: true, fallback_locale: "none")
      manifest = ParademCmsSite::Manifest.load(root: root)
      source = File.read(File.join(root, "app/queries/article_query.rb"))
      expected = ParademCmsSite::QueryGeneration::QueryGenerator.from_manifest(manifest).generate("Article", dry_run: true).fetch(:contents)
      assert_equal expected, source
      assert_equal overrides, File.binread(File.join(root, "app/queries/overrides.yml"))
      assert_operator source.index("fallback_locale :none"), :<, source.index("graphql_fields")
      first = snapshot(root)
      generate(:resource, root, "Article", singleton: true, fallback_locale: "none")
      assert_equal first, snapshot(root)
    end
    [{"Article" => {"silently_ignored" => true}}, {"Article" => {"fallback_locale" => "invalid!"}}, {"Article" => {"excluded_fields" => [], "exclude_fields" => []}}].each do |overrides|
      with_app do |root|
        configure_generated_site(root, overrides)
        before = snapshot(root)
        assert_raises(ArgumentError) { generate(:resource, root, "Article") }
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_hidden_or_aliased_generated_projections_must_match_the_resource_contract
    [{"Article" => {"excluded_fields" => ["title"]}}, {"Article" => {"field_aliases" => {"permalink" => "different_path"}}}].each do |overrides|
      with_app do |root|
        configure_generated_site(root, overrides)
        before = snapshot(root)
        assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article") }
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_presentation_namespace_cannot_collide_with_a_host_model_or_constant
    with_app do |root|
      File.write(File.join(root, "app/models/site.rb"), "raise \"Do not execute host model code\"\n")
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:theme, root, "journal") }
      assert_equal before, snapshot(root)
      File.unlink(File.join(root, "app/models/site.rb"))
      refute Object.const_defined?(:Site, false)
      Object.const_set(:Site, Class.new)
      created = true
      before = snapshot(root)
      assert_raises(Rails::Generators::Error) { generate(:resource, root, "Article") }
      assert_equal before, snapshot(root)
    ensure
      Object.send(:remove_const, :Site) if created
    end
  end

  def test_malformed_ownership_metadata_cannot_partially_generate
    [[], {"version" => 999, "generators" => {}, "managed_files" => {}}, {"version" => 1, "generators" => {}, "managed_files" => {"config/cms_site.yml" => "bad"}}].each do |metadata|
      with_app do |root|
        File.write(File.join(root, ParademCmsSite::Generators::Base::STATE_PATH), JSON.generate(metadata))
        before = snapshot(root)
        assert_raises(Rails::Generators::Error) { generate(:block, root, "promo", force: true) }
        assert_equal before, snapshot(root)
      end
    end
  end

  def test_ambient_credentials_never_enter_outputs_or_diagnostics
    old = ENV["DATO_API_TOKEN"]
    ENV["DATO_API_TOKEN"] = "sentinel-generator-token-not-live"
    with_app do |root|
      output = generate(:theme, root, "journal").join + generate(:resource, root, "Article").join + generate(:block, root, "promo").join
      refute_includes output, ENV.fetch("DATO_API_TOKEN")
      snapshot(root).each_value { |contents| refute_includes contents, ENV.fetch("DATO_API_TOKEN") }
      before = snapshot(root)
      error = assert_raises(Rails::Generators::Error) { generate(:block, root, "promo", layout: "wide", force: true) }
      refute_includes error.message, ENV.fetch("DATO_API_TOKEN")
      assert_equal before, snapshot(root)
    end
  ensure
    old.nil? ? ENV.delete("DATO_API_TOKEN") : ENV["DATO_API_TOKEN"] = old
  end

  def test_every_generated_ruby_file_parses_and_destroy_is_not_implicit
    with_app do |root|
      generate(:theme, root, "journal")
      generate(:resource, root, "Article", body: "body", theme: "journal")
      generate(:block, root, "promo")
      snapshot(root).each do |path, source|
        refute_nil Ripper.sexp(source), path if path.end_with?(".rb")
      end
      before = snapshot(root)
      generator = GENERATORS.fetch(:block).new(["promo"], {}, destination_root: root, behavior: :revoke)
      assert_raises(Rails::Generators::Error) { capture_io { generator.generate_block } }
      assert_equal before, snapshot(root)
    end
  end
end
