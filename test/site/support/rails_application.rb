# frozen_string_literal: true

require "open3"
require "rbconfig"

module RailsApplicationFixture
  ROOT = File.expand_path("../../..", __dir__)
  SKIPS = %w[--skip-bundle --skip-git --skip-docker --skip-kamal --skip-ci --skip-javascript --skip-hotwire
    --skip-asset-pipeline --skip-jbuilder --skip-solid --skip-system-test --skip-test --skip-bootsnap
    --skip-dev-gems --skip-rubocop --skip-brakeman --skip-bundler-audit --skip-thruster
    --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable].freeze

  def source_snapshot(app)
    Dir.glob(File.join(app, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) && path.match?(/(?:\.(rb|erb|css|json|ya?ml|md)|\/Gemfile(?:\.lock)?)\z/) }.to_h do |path|
      [path.delete_prefix("#{app}/"), File.binread(path)]
    end
  end

  def retain_browser_evidence(app, suite)
    return unless app
    output = File.join(ROOT, "tmp/#{suite}-evidence", RUBY_VERSION, Gem.loaded_specs.fetch("railties").version.to_s)
    FileUtils.rm_rf(output)
    FileUtils.mkdir_p(output)
    %w[accessibility screenshots].each do |name|
      source = File.join(app, "tmp", name)
      FileUtils.cp_r(source, output) if File.directory?(source)
    end
    gems = Gem.loaded_specs.slice(*%w[railties activerecord json view_component propshaft importmap-rails turbo-rails tailwindcss-ruby puma selenium-webdriver axe-core-api]).transform_values { |spec| spec.version.to_s }
    File.write(File.join(output, "environment.json"), JSON.pretty_generate({"ruby" => RUBY_VERSION, "platform" => RUBY_PLATFORM, "gems" => gems}) + "\n")
  end

  def command(environment, *arguments, chdir:, success: true)
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, *arguments, chdir: chdir, unsetenv_others: true)
    if success
      assert status.success?, "#{arguments.first(3).join(" ")} failed:\n#{stdout}\n#{stderr}"
    else
      refute status.success?, "Command unexpectedly succeeded: #{stdout}"
    end
    stdout + stderr
  end

  def with_application(ui: false)
    Dir.mktmpdir("cms-fresh-rails-") do |directory|
      guard = File.join(directory, "no_network.rb")
      File.write(guard, <<~RUBY)
        require "net/http"
        Net::HTTP.prepend(Module.new do
          private

          def connect
            unless #{ui} && %w[localhost 127.0.0.1 ::1].include?(address)
              raise IOError, "Network forbidden in Rails installation fixtures"
            end
            super
          end
        end)
      RUBY
      environment = %w[PATH HOME GEM_HOME GEM_PATH SE_CHROMEDRIVER SE_SKIP_DRIVER_IN_PATH].to_h { |key| [key, ENV[key]] }.merge(
        "BUNDLE_GEMFILE" => Bundler.default_gemfile.to_s, "RUBYOPT" => "-r#{guard}", "RAILS_ENV" => "test",
        "SECRET_KEY_BASE" => "synthetic-test-secret-key-base-#{"0" * 64}",
        "DATO_API_TOKEN" => "sentinel-cms-token-not-live", "DATO_WEBHOOK_SECRET" => "fixture-webhook-secret"
      )
      app = File.join(directory, "fixture_site")
      command(environment, "-rbundler/setup", "-S", "rails", "new", app, *SKIPS, "--quiet", chdir: ROOT)
      components = %w[railties activerecord activejob actionpack sqlite3 json].map { |name| gem_declaration(name, require_false: true) }
      if ui
        components += %w[view_component propshaft importmap-rails turbo-rails tailwindcss-rails].map { |name| gem_declaration(name) }
        components += %w[minitest capybara selenium-webdriver axe-core-capybara puma].map { |name| gem_declaration(name, require_false: true) }
      end
      File.write(File.join(app, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        #{components.join("\n")}
        gem "dato_cms_graphql", path: #{ROOT.inspect}, require: "paradem_cms_site"
      RUBY
      environment["BUNDLE_GEMFILE"] = File.join(app, "Gemfile")
      command(environment, "-S", "bundle", "lock", "--local", chdir: app)
      if ui
        %w[app/assets/tailwind app/javascript].each { |path| FileUtils.mkdir_p(File.join(app, path)) }
        File.write(File.join(app, "app/assets/tailwind/application.css"), "@import \"tailwindcss\" source(none);\n")
        File.write(File.join(app, "app/javascript/application.js"), "import \"@hotwired/turbo-rails\"\n")
        File.write(File.join(app, "config/importmap.rb"), "pin \"application\"\npin \"@hotwired/turbo-rails\", to: \"turbo.min.js\"\n")
        environment["DATO_API_TOKEN"] = nil
        environment["DATO_WEBHOOK_SECRET"] = nil
      end
      yield app, environment
    end
  end

  def gem_declaration(name, require_false: false)
    "gem #{name.inspect}, #{Gem.loaded_specs.fetch(name).version.to_s.inspect}#{", require: false" if require_false}"
  end

  def rails(app, environment, *arguments, **options)
    command(environment, File.join(app, "bin/rails"), *arguments, chdir: app, **options)
  end
end
