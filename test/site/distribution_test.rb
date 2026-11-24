# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class DistributionTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def specification
    Gem::Specification.load(File.join(ROOT, "dato_cms_graphql.gemspec"))
  end

  def test_one_mit_distribution_without_private_or_rails_runtime_dependencies
    spec = specification
    assert_equal "MIT", spec.license
    assert_equal DatoCmsGraphql::VERSION, ParademCmsSite::VERSION
    assert_equal DatoCmsGraphql::VERSION, spec.version.to_s
    assert_equal "cms-site", spec.executables.fetch(0)
    assert_empty spec.runtime_dependencies.map(&:name) & %w[paradem_cms_site railties activerecord activejob actionpack sqlite3 view_component propshaft importmap-rails turbo-rails tailwindcss-rails capybara selenium-webdriver axe-core-capybara puma]
    refute Gem.loaded_specs.key?("paradem_cms_site")
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("4.0.10"))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("4.0.9"))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.4.5"))
    support = spec.runtime_dependencies.find { |dependency| dependency.name == "activesupport" }.requirement
    assert support.satisfied_by?(Gem::Version.new("8.1.4.1"))
    refute support.satisfied_by?(Gem::Version.new("8.1.4"))
    refute support.satisfied_by?(Gem::Version.new("8.0.5.2"))
    refute support.satisfied_by?(Gem::Version.new("8.2.0"))
    graphql = spec.runtime_dependencies.find { |dependency| dependency.name == "graphql" }.requirement
    assert graphql.satisfied_by?(Gem::Version.new("2.6.16"))
    refute graphql.satisfied_by?(Gem::Version.new("2.6.15"))
  end

  def test_package_includes_all_integration_entry_points_and_no_private_or_development_files
    files = specification.files
    %w[lib/paradem_cms_site.rb lib/paradem_cms_site/rails/installation.rb
      lib/paradem_cms_site/tasks.rake lib/generators/paradem_cms_site/install/install_generator.rb
      lib/generators/paradem_cms_site/base.rb
      lib/generators/paradem_cms_site/resource/resource_generator.rb
      lib/generators/paradem_cms_site/block/block_generator.rb
      lib/generators/paradem_cms_site/theme/theme_generator.rb
      lib/paradem_cms_site/testing/system_test_case.rb
      lib/paradem_cms_site/sync/file_lock.rb exe/cms-site docs/installation.md LICENSE.txt].each do |path|
      assert_includes files, path
    end
    assert_empty files.grep(%r{\A(?:test/|\.github/|\.obr/|\.git/|config/|Gemfile|AGENTS\.md|PLAN\.org)})
    assert_empty files.grep(/(?:\.key|\.sqlite3|\.dump|\.enc|\.env|paradem_cms_site\.gemspec)\z/)
  end

  def test_tooling_and_client_entry_points_remain_independently_loadable_without_rails_or_network
    ['require "paradem_cms_site/sync"; require "paradem_cms_site/query_generation"',
      'ENV["TEST"] = "true"; require "dato_cms_graphql"'].each do |requires|
      stdout, stderr, status = Open3.capture3({"DATO_API_TOKEN" => "synthetic-not-live"}, RbConfig.ruby, "-Ilib", "-e", <<~RUBY, chdir: ROOT)
        require "net/http"
        Net::HTTP.prepend(Module.new do
          def request(*) = raise("Unexpected network")
        end)
        #{requires}
        abort "Rails loaded" if defined?(Rails::Application)
        abort "ActiveRecord loaded" if defined?(ActiveRecord::Base)
        abort "Private gem loaded" if Gem.loaded_specs.key?("paradem_cms_site")
        puts "OFFLINE_LOAD_PASS"
      RUBY
      assert status.success?, stderr
      assert_equal "OFFLINE_LOAD_PASS\n", stdout
    end
  end
end
