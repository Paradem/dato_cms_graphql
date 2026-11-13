require "test_helper"
require "i18n"

class ModelIteratorTest < Minitest::Test
  class SyntheticQuery
    INDEX = :synthetic_index
    META_DATA = :synthetic_meta
    attr_reader :attributes

    def self.graphql_page_size
      2
    end

    def initialize(attributes)
      @attributes = attributes
    end
  end

  def setup
    @previous_locales = I18n.available_locales
    @previous_count = DatoCmsGraphql.method(:count)
    @previous_query = DatoCmsGraphql.method(:query)
    I18n.available_locales = [:en, :fr]
    @requests = requests = []
    DatoCmsGraphql.define_singleton_method(:count) { |_query| 3 }
    DatoCmsGraphql.define_singleton_method(:query) do |query, variables:|
      requests << [query, variables]
      skip = variables.fetch(:skip)
      %w[en fr].to_h do |locale|
        ["#{locale}_items", (skip...[skip + 2, 3].min).map { |index| {"id" => "#{locale}-#{index}"} }]
      end
    end
    @iterator = DatoCmsGraphql::ModelIterator.new(SyntheticQuery)
  end

  def teardown
    DatoCmsGraphql.define_singleton_method(:count, @previous_count)
    DatoCmsGraphql.define_singleton_method(:query, @previous_query)
    I18n.available_locales = @previous_locales
  end

  def test_enumeration_count_and_localized_order
    I18n.with_locale(:fr) do
      assert_equal 3, @iterator.count
      assert_empty @requests
      assert_equal %w[fr-0 fr-1 fr-2], @iterator.each.map { |item| item.attributes.fetch("id") }
    end
  end

  def test_legacy_array_indexing_and_slices
    I18n.with_locale(:en) do
      assert_equal "en-0", @iterator[0].attributes.fetch("id")
      assert_equal "en-2", @iterator[-1].attributes.fetch("id")
      assert_nil @iterator[3]
      assert_equal %w[en-0 en-1], @iterator[0, 2].map { |item| item.attributes.fetch("id") }
      assert_equal %w[en-1 en-2], @iterator[1..].map { |item| item.attributes.fetch("id") }
    end
  end

  def test_each_still_streams_without_prefetching_every_page
    I18n.with_locale(:en) { @iterator.each { |_item| break } }
    assert_equal [[SyntheticQuery::INDEX, {skip: 0}]], @requests
  end

  def test_page_requests_stop_at_the_declared_count
    {
      0 => [],
      1 => [0],
      2 => [0],
      3 => [0, 2],
      4 => [0, 2],
      5 => [0, 2, 4]
    }.each do |total, expected_skips|
      stub_records(total)
      iterator = DatoCmsGraphql::ModelIterator.new(SyntheticQuery)
      I18n.with_locale(:en) do
        ids = iterator.each.map { |item| item.attributes.fetch("id") }
        assert_equal((0...total).map { |index| "en-#{index}" }, ids, "count=#{total}")
      end
      assert_equal total, iterator.count
      assert_equal expected_skips, @requests.map { |_query, variables| variables.fetch(:skip) }, "count=#{total}"
    end
  end

  private

  def stub_records(total)
    requests = @requests = []
    DatoCmsGraphql.define_singleton_method(:count) { |_query| total }
    DatoCmsGraphql.define_singleton_method(:query) do |query, variables:|
      requests << [query, variables]
      skip = variables.fetch(:skip)
      last = [skip + 2, total].min
      %w[en fr].to_h do |locale|
        ["#{locale}_items", (skip...last).map { |index| {"id" => "#{locale}-#{index}"} }]
      end
    end
  end
end
