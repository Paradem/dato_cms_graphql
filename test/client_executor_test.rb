require "test_helper"
require "dato_cms_graphql/client_executor"

class ClientExecutorTest < Minitest::Test
  def test_uses_only_the_injected_client_and_snapshots_context
    calls = []
    client = Object.new
    client.define_singleton_method(:query) do |definition, variables:, context:|
      calls << [definition, variables, context]
      GraphQL::Client::Response.new({}, data: {"enItems" => [{"id" => "synthetic", "shortTitle" => "Synthetic"}]})
    end
    context = {include_drafts: false}
    executor = DatoCmsGraphql::ClientExecutor.new(client: client, context: context)
    context[:include_drafts] = true
    assert_equal({"en_items" => [{"id" => "synthetic", "short_title" => "Synthetic"}]}, executor.query(:index, variables: {skip: 2}))
    assert_equal [[:index, {skip: 2}, {include_drafts: false}]], calls
    assert_equal true, context[:include_drafts]
  end

  def test_checks_nested_errors_and_counts_without_exposing_response_details
    client = Object.new
    client.define_singleton_method(:query) do |*args, **|
      GraphQL::Client::Response.new({}, data: {"enItems" => []},
        errors: GraphQL::Client::Errors.new([{"message" => "synthetic-private-detail", "normalizedPath" => ["data", "enItems", 0, "title"]}]))
    end
    executor = DatoCmsGraphql::ClientExecutor.new(client: client)
    error = assert_raises(DatoCmsGraphql::Error) { executor.query(:index) }
    refute_includes error.message, "synthetic-private-detail"
    [nil, -1, "2", 2].each do |value|
      client.define_singleton_method(:query) { |*args, **| GraphQL::Client::Response.new({}, data: {"metaData" => {"count" => value}}) }
      if value == 2
        assert_equal 2, executor.count(:metadata)
      else
        assert_raises(DatoCmsGraphql::Error) { executor.count(:metadata) }
      end
    end
  end

  def test_existing_collection_and_singleton_helpers_use_a_scoped_executor
    previous_locales = I18n.available_locales
    I18n.available_locales = [:en]
    calls = []
    executor = Object.new
    executor.define_singleton_method(:count) { |_| 1 }
    executor.define_singleton_method(:query) do |definition, variables: {}|
      calls << definition
      if definition == :single
        {"en_item" => {"id" => "synthetic-single", "slug" => "singleton"}}
      else
        {"en_items" => variables.fetch(:skip).zero? ? [{"id" => "synthetic-page", "slug" => "page"}] : []}
      end
    end
    collection = Class.new(DatoCmsGraphql::BaseQuery)
    collection.const_set(:INDEX, :index)
    collection.const_set(:META_DATA, :metadata)
    collection.define_singleton_method(:executor) { executor }
    assert_equal ["synthetic-page"], collection.all.map(&:id)
    assert_equal "page", collection.all[0].slug
    single = Class.new(DatoCmsGraphql::BaseQuery)
    single.single_instance(true)
    single.const_set(:SINGLE, :single)
    single.define_singleton_method(:executor) { executor }
    assert_equal "synthetic-single", single.get.id
    assert_equal "singleton", single.get.slug
    assert_includes calls, :single
    assert_equal DatoCmsGraphql, DatoCmsGraphql::BaseQuery.executor
  ensure
    I18n.available_locales = previous_locales
  end
end
