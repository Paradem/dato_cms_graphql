require "test_helper"
require "json"
require "open3"
require "rbconfig"

class RefreshBenchmarkTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_small_synthetic_run_reports_valid_phases_and_memory
    environment = {"ROWS" => "5", "PAYLOAD_KB" => "1", "LOCALES" => "en"}
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, "-rbundler/setup", "benchmark/refresh.rb", chdir: ROOT)
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal 6, result.dig("dataset", "synthetic_records")
    assert_operator result.dig("dataset", "database_bytes"), :>, 0
    assert_operator result.dig("timings_ms", "fetch_validate_materialize"), :>=, 0
    assert_operator result.dig("timings_ms", "delete_insert"), :>=, 0
    assert_operator result.dig("timings_ms", "total"), :>, 0
    assert_operator result.fetch("peak_rss_mb"), :>, 0
    assert_equal RUBY_VERSION, result.dig("platform", "ruby")
  end
end
