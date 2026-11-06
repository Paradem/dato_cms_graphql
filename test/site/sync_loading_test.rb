# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class SyncLoadingTest < Minitest::Test
  def test_loading_runtime_api_does_not_load_rails_active_record_or_a_client
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", <<~RUBY)
      require "paradem_cms_site/sync"
      abort "Rails loaded" if defined?(Rails)
      abort "ActiveRecord loaded" if defined?(ActiveRecord)
      abort "Client loaded" if %i[Client HTTP Schema].any? { |name| DatoCmsGraphql.const_defined?(name, false) }
      abort "Global loader loaded" if $LOADED_FEATURES.any? { |path| path.end_with?("/dato_cms_graphql.rb") }
      puts ParademCmsSite::Sync.name
    RUBY
    assert status.success?, stderr
    assert_equal "ParademCmsSite::Sync\n", stdout
  end
end
