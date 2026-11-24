# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/rails_application"
require "json"

class RailsUiInstallationTest < Minitest::Test
  include RailsApplicationFixture

  def source_snapshot(app)
    Dir.glob(File.join(app, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) && path.match?(/\.(rb|erb|css|json|ya?ml|md)\z/) }.to_h do |path|
      [path.delete_prefix("#{app}/"), File.binread(path)]
    end
  end

  def test_real_rails_ui_generators_requests_components_assets_and_required_browser_fixtures
    with_application(ui: true) do |app, environment|
      install = %w[generate paradem_cms_site:install --site=ui_fixture --fixture --models=Page,Global --singletons=Global --locales=en,fr]
      rails(app, environment, *install)
      original = source_snapshot(app)
      rails(app, environment, *install)
      assert_equal original, source_snapshot(app)
      args = [
        %w[generate paradem_cms_site:theme journal],
        %w[generate paradem_cms_site:resource Article --body=body --permalink=slug --fallback-locale=none --theme=journal],
        %w[generate paradem_cms_site:resource Home --singleton --fallback-locale=none --theme=journal],
        %w[generate paradem_cms_site:block promo --layout=wide]
      ]
      before = source_snapshot(app)
      rails(app, environment, *args.first, "--pretend")
      assert_equal before, source_snapshot(app)
      pins = File.binread(File.join(app, "config/importmap.rb"))
      args.each { |arguments| rails(app, environment, *arguments) }
      first = source_snapshot(app)
      args.each { |arguments| rails(app, environment, *arguments) }
      assert_equal first, source_snapshot(app)
      assert_equal pins, File.binread(File.join(app, "config/importmap.rb"))
      assert_empty (first.keys - original.keys).grep(%r{\Aapp/(?:services|jobs)/})
      conflict = File.join(app, "test/components/site/story_component_test.rb")
      File.write(conflict, "# Host-owned fixture, never overwrite\n")
      before_conflict = source_snapshot(app)
      failure = rails(app, environment, "generate", "paradem_cms_site:resource", "Story", "--force", success: false)
      assert_includes failure, "Refusing to overwrite"
      assert_equal before_conflict, source_snapshot(app)
      rails(app, environment, "db:migrate")
      assert_includes rails(app, environment, "cms:doctor"), "OK ui_fixture"
      rails(app, environment, "cms:sync")
      check = <<~RUBY
        abort "Wrong fixture count" unless CmsRecord.count == 8
        abort "Lost slug projection" unless Article.find_by!(locale: :fr).permalink == "fr-article"
        abort "Lost locale fixture" unless Home.find_by!(locale: :fr).title == "Synthetic Home (fr)"
        abort "Global client loaded" if DatoCmsGraphql.const_defined?(:Client, false)
        puts "GENERATED_CACHE_PASS"
      RUBY
      assert_includes rails(app, environment, "runner", check), "GENERATED_CACHE_PASS"
      rails(app, environment, "tailwindcss:build")
      unit = rails(app, environment, "test")
      assert_match(/6 (?:runs|tests), \d+ assertions, 0 failures, 0 errors, 0 skips/, unit)
      puts "Generated app: #{unit.lines.find { |line| line.include?("0 failures, 0 errors, 0 skips") }.to_s.strip}"
      browser = rails(app, environment, "test:system")
      assert_match(/3 (?:runs|tests), \d+ assertions, 0 failures, 0 errors, 0 skips/, browser)
      puts "Generated browser: #{browser.lines.find { |line| line.include?("0 failures, 0 errors, 0 skips") }.to_s.strip}"
      reports = Dir[File.join(app, "tmp/accessibility/*.json")].map { |path| JSON.parse(File.read(path)) }
      assert_equal 12, reports.length
      assert reports.all? { |report| report.fetch("violations").empty? }
      assert_equal [[390, 844], [1280, 900]], reports.map { |report| report.fetch("testEnvironment").values_at("windowWidth", "windowHeight") }.uniq.sort
      screenshots = Dir[File.join(app, "tmp/screenshots/cms-*.png")]
      assert_equal 12, screenshots.length
      # Only this disposable app leaves fixture mode for a credential-free production build.
      manifest_path = File.join(app, "config/cms_site.yml")
      manifest = YAML.safe_load_file(manifest_path)
      manifest.fetch("rails").delete("fixture_data")
      File.write(manifest_path, YAML.dump(manifest))
      production = environment.merge("RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1")
      rails(app, production, "zeitwerk:check")
      rails(app, production, "assets:precompile")
      css = Dir[File.join(app, "public/assets/tailwind-*.css")].map { |path| File.read(path) }.join
      assert_includes css, ".max-w-7xl"
      assert_includes css, ".font-site-heading"
      assert_includes css, "--cms-surface"
    ensure
      if app
        output = File.join(ROOT, "tmp/generator-evidence")
        FileUtils.mkdir_p(output)
        %w[accessibility screenshots].each do |name|
          source = File.join(app, "tmp", name)
          FileUtils.cp_r(source, output) if File.directory?(source)
        end
      end
    end
  end
end
