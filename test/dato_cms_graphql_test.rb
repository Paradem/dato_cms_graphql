require "test_helper"
require "tmpdir"

class DatoCmsGraphqlTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::DatoCmsGraphql::VERSION
  end

  def test_it_does_something_useful
    assert true
  end

  def test_queries_path_starts_as_nil
    assert DatoCmsGraphql.path_to_queries.nil?
  end

  def test_query_files_load_on_all_supported_ruby_versions
    previous_path = DatoCmsGraphql.path_to_queries
    previous_queries = DatoCmsGraphql.instance_variable_get(:@queries)
    Dir.mktmpdir("dato-query-registry-") do |directory|
      File.write(File.join(directory, "synthetic_query.rb"), "module DatoCmsGraphql; QueryRegistryFixture = true; end\n")
      DatoCmsGraphql.path_to_queries = directory
      DatoCmsGraphql.instance_variable_set(:@queries, nil)
      assert_kind_of Array, DatoCmsGraphql.queries
      assert DatoCmsGraphql::QueryRegistryFixture
    end
  ensure
    DatoCmsGraphql.path_to_queries = previous_path
    DatoCmsGraphql.instance_variable_set(:@queries, previous_queries)
    DatoCmsGraphql.send(:remove_const, :QueryRegistryFixture) if DatoCmsGraphql.const_defined?(:QueryRegistryFixture, false)
  end

  def test_queries_path_can_be_set
    DatoCmsGraphql.path_to_queries = "/app/queries"
    assert_equal DatoCmsGraphql.path_to_queries, "/app/queries"
    DatoCmsGraphql.path_to_queries = nil
  end
end
