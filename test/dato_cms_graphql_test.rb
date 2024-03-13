require "test_helper"

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

  def test_queries_path_can_be_set
    DatoCmsGraphql.path_to_queries = "/app/queries"
    assert_equal DatoCmsGraphql.path_to_queries, "/app/queries"
    DatoCmsGraphql.path_to_queries = nil
  end
end
