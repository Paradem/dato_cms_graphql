require "test_helper"
require "tmpdir"

class ConcurrencyTest < Minitest::Test
  def test_path_to_queries_thread_safety
    threads = []
    10.times do
      threads << Thread.new { DatoCmsGraphql.path_to_queries = "/test/path" }
    end
    threads.each(&:join)
    assert_equal "/test/path", DatoCmsGraphql.path_to_queries
  end

  def test_queries_loading_concurrency
    Dir.mktmpdir do |dir|
      DatoCmsGraphql.path_to_queries = dir
      threads = 5.times.map { Thread.new { DatoCmsGraphql.queries } }
      threads.each(&:join)
    end
  ensure
    DatoCmsGraphql.path_to_queries = nil
  end
end
