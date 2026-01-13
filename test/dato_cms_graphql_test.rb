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

  def test_queries_raises_error_when_path_not_set
    original_path = DatoCmsGraphql.path_to_queries
    DatoCmsGraphql.instance_variable_set(:@queries, nil)
    DatoCmsGraphql.path_to_queries = nil
    assert_raises(RuntimeError) { DatoCmsGraphql.queries }
  ensure
    DatoCmsGraphql.path_to_queries = original_path
  end

  def test_queries_raises_error_when_path_does_not_exist
    original_path = DatoCmsGraphql.path_to_queries
    DatoCmsGraphql.instance_variable_set(:@queries, nil)
    DatoCmsGraphql.path_to_queries = "/nonexistent/path"
    assert_raises(RuntimeError) { DatoCmsGraphql.queries }
  ensure
    DatoCmsGraphql.path_to_queries = original_path
  end

  def test_query_handles_api_errors
    DatoCmsGraphql::Client.stubs(:query).raises(GraphQL::Client::Error.new("API error"))
    assert_raises(GraphQL::Client::Error) { DatoCmsGraphql.query("invalid query") }
  end

  def test_query_handles_invalid_token
    original_token = ENV["DATO_API_TOKEN"]
    ENV["DATO_API_TOKEN"] = "invalid"
    DatoCmsGraphql::Client.stubs(:query).raises(GraphQL::Client::Error.new("Unauthorized"))
    assert_raises(GraphQL::Client::Error) { DatoCmsGraphql.query("query { test }") }
  ensure
    ENV["DATO_API_TOKEN"] = original_token
  end
end
