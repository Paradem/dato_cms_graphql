# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/rails_application"
require "json"

class RailsPortabilityTest < Minitest::Test
  include RailsApplicationFixture

  FIXTURES = File.expand_path("fixtures/portability", __dir__)

  def generate_site(app, environment)
    commands = [
      %w[install --site=portability --fixture --locales=en,fr --models=Page,Global --singletons=Global],
      %w[theme journal], %w[theme folio],
      %w[resource Article --body=body --permalink=slug --fallback-locale=none --theme=journal],
      %w[resource Home --singleton --fallback-locale=none --theme=journal],
      %w[block promo --layout=wide]
    ]
    commands.each { |kind, *args| rails(app, environment, "generate", "paradem_cms_site:#{kind}", *args) }
  end

  def customize_host(app)
    %w[journal folio].each do |theme|
      FileUtils.cp(File.join(FIXTURES, "#{theme}.html.erb"), File.join(app, "app/views/layouts/site/#{theme}.html.erb"))
      css_path = File.join(app, "app/assets/tailwind/themes/#{theme}.css")
      aliases = File.read(css_path).match(/@theme inline.*\z/m).to_s
      File.write(css_path, File.read(File.join(FIXTURES, "#{theme}.css")) + "\n" + aliases)
      controller = File.join(app, "app/controllers/site/#{theme}_theme_controller.rb")
      source = File.read(controller).sub("      # This public fixture never reads CMS records or contacts a provider.", <<~RUBY.chomp)
        @article = Article.localized.where(render: true).first!
        @home = Home.localized.where(render: true).first!
        @promo = JSON.parse(Rails.root.join("test/fixtures/files/cms_block_promo.json").read)
      RUBY
      File.write(controller, source)
      File.write(File.join(app, "app/views/site/#{theme}_theme/show.html.erb"), '<%= render "site/portability/content" %>' + "\n")
      # Replace preview-only tests with the required shared two-shell/cache/Turbo contract.
      File.unlink(File.join(app, "test/system/cms_#{theme}_theme_test.rb"))
    end
    directory = File.join(app, "app/views/site/portability")
    FileUtils.mkdir_p(directory)
    FileUtils.cp(File.join(FIXTURES, "content.html.erb"), File.join(directory, "_content.html.erb"))
    FileUtils.cp(File.join(FIXTURES, "browser_contract.rb"), File.join(app, "test/system/cms_portability_test.rb"))
    fixture_path = File.join(app, "config/cms/fixture.json")
    data = JSON.parse(File.read(fixture_path))
    data.fetch("Article").each do |locale, rows|
      rows.first["title"] += " long content" * 12
      rows.first["body"] = nil if locale == "fr"
    end
    File.write(fixture_path, JSON.pretty_generate(data) + "\n")
  end

  def reproducible_sources(app)
    source_snapshot(app).to_h do |path, contents|
      [path.sub(%r{\Adb/migrate/\d+_}, "db/migrate/TIMESTAMP_"), contents]
    end
  end

  def cache_digest(app, environment)
    script = <<~'RUBY'
      require "digest"
      rows = CmsRecord.order(:type, :locale, :cms_id).pluck(:type, :locale, :cms_id, :permalink, :cms_record)
      puts "CACHE_DIGEST=#{Digest::SHA256.hexdigest(rows.to_json)}"
    RUBY
    result = rails(app, environment, "runner", script).lines.grep(/\ACACHE_DIGEST=/).first
    refute_nil result
    result
  end

  def test_two_fresh_sites_are_reproducible_and_host_themes_preserve_runtime_and_rollback
    with_application(ui: true) do |app, environment|
      generate_site(app, environment)
      generated = source_snapshot(app)
      %w[journal folio].each { |theme| rails(app, environment, "generate", "paradem_cms_site:theme", theme) }
      assert_equal generated, source_snapshot(app)
      customize_host(app)
      expected = reproducible_sources(app)
      with_application(ui: true) do |second, second_environment|
        generate_site(second, second_environment)
        customize_host(second)
        assert_equal expected, reproducible_sources(second), "Independent bootstraps must differ only in migration timestamp filenames"
      end
      before = source_snapshot(app)
      error = rails(app, environment, "generate", "paradem_cms_site:theme", "folio", "--force", success: false)
      assert_includes error, "Refusing to overwrite"
      assert_equal before, source_snapshot(app)
      rails(app, environment, "db:migrate")
      FileUtils.cp(File.join(FIXTURES, "safety_check.rb"), File.join(app, "tmp/safety_check.rb"))
      assert_includes rails(app, environment, "runner", File.join(app, "tmp/safety_check.rb")), "GENERATED_CACHE_SAFETY_PASS"
      assert_includes rails(app, environment, "cms:doctor"), "OK portability"
      verify_matched_rollback(app, environment)
      rails(app, environment, "tailwindcss:build")
      browser = rails(app, environment, "test:system")
      assert_match(/3 (?:runs|tests), \d+ assertions, 0 failures, 0 errors, 0 skips/, browser)
      puts "Two-shell browser: #{browser.lines.find { |line| line.include?("0 failures, 0 errors, 0 skips") }.to_s.strip}"
      reports = Dir[File.join(app, "tmp/accessibility/CmsThemePortabilitySystemTest-*.json")].map { |path| JSON.parse(File.read(path)) }
      assert_equal 16, reports.length
      assert reports.all? { |report| report.fetch("violations").empty? }
      assert_equal [[390, 844], [1280, 900]], reports.map { |report| report.fetch("testEnvironment").values_at("windowWidth", "windowHeight") }.uniq.sort
      assert_equal 8, Dir[File.join(app, "tmp/screenshots/portability-*.png")].length
      unit = rails(app, environment, "test")
      assert_match(/7 (?:runs|tests), \d+ assertions, 0 failures, 0 errors, 0 skips/, unit)
      puts "Two-shell app: #{unit.lines.find { |line| line.include?("0 failures, 0 errors, 0 skips") }.to_s.strip}"
      manifest_path = File.join(app, "config/cms_site.yml")
      manifest = YAML.safe_load_file(manifest_path)
      manifest.fetch("rails").delete("fixture_data")
      File.write(manifest_path, YAML.dump(manifest))
      production = environment.merge("RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1")
      rails(app, production, "zeitwerk:check")
      rails(app, production, "assets:precompile")
      css = Dir[File.join(app, "public/assets/tailwind-*.css")].map { |path| File.read(path) }.join
      %w[journal folio .proof-rail .proof-header .max-w-7xl].each { |token| assert_includes css, token }
    ensure
      retain_browser_evidence(app, "portability")
    end
  end

  def verify_matched_rollback(app, environment)
    baseline = source_snapshot(app)
    digest = cache_digest(app, environment)
    backup = File.join(app, "tmp/last-good.sqlite3")
    rails(app, environment, "runner", "connection = CmsRecord.connection; connection.execute(\"VACUUM INTO \" + connection.quote(#{backup.inspect}))")
    schema = File.join(app, "config/cms/schema.graphql")
    query = File.join(app, "app/queries/article_query.rb")
    fixture = File.join(app, "config/cms/fixture.json")
    File.write(schema, File.read(schema).sub("type ArticleRecord {", "type ArticleRecord { edition: String,"))
    File.write(query, File.read(query).sub("graphql_fields(", "graphql_fields(:edition, "))
    data = JSON.parse(File.read(fixture))
    data.fetch("Article").each_value { |rows| rows.first["edition"] = "candidate-two" }
    File.write(fixture, JSON.pretty_generate(data) + "\n")
    assert_includes rails(app, environment, "cms:doctor"), "OK portability"
    rails(app, environment, "cms:sync")
    candidate = cache_digest(app, environment)
    refute_equal digest, candidate, "The upgrade probe must actually change cached content"
    File.write(query, File.read(query).sub(":edition", ":unavailable_field"))
    assert_includes rails(app, environment, "cms:doctor", success: false), "query/schema"
    assert_equal candidate, cache_digest(app, environment), "Failed qualification must not mutate candidate data"
    baseline.each { |path, contents| File.binwrite(File.join(app, path), contents) }
    # Every Rails subprocess has exited; restore a coherent SQLite backup, not a live WAL copy.
    database = File.join(app, "storage/test.sqlite3")
    FileUtils.rm_f(["#{database}-wal", "#{database}-shm"])
    FileUtils.cp(backup, database)
    assert_equal baseline, source_snapshot(app)
    assert_equal digest, cache_digest(app, environment), "Matched source/schema/query/cache cutback must restore the original projection"
    assert_includes rails(app, environment, "cms:doctor"), "OK portability"
  end
end
