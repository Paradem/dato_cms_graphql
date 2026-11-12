# frozen_string_literal: true

require_relative "test_helper"
require "i18n"
require "graphql"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/inclusion"
require "active_support/core_ext/string/inflections"
require "dato_cms_graphql/fields"
require "dato_cms_graphql/base_query"
require "paradem_cms_site/sync"

class RegionalLocaleTest < Minitest::Test
  Response = Struct.new(:data, :errors)
  Errors = Struct.new(:all)

  class Client
    def initialize(payload)
      @payload = payload
    end

    def query(operation, variables:, context:)
      data = (operation == "count") ? {"meta_data" => {"count" => 1}} : @payload
      Response.new(data, Errors.new([]))
    end
  end

  def setup
    @locales = I18n.available_locales
    @default = I18n.default_locale
    @current = I18n.locale
    I18n.available_locales = [:"en-US", :fr]
    I18n.default_locale = :"en-US"
    I18n.locale = :"en-US"
  end

  def teardown
    I18n.available_locales = @locales
    I18n.default_locale = @default
    I18n.locale = @current
  end

  def build_query(name, single: false, fallback: nil)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
    klass = Class.new(DatoCmsGraphql::BaseQuery)
    # Keep the compiled query text instead of parsing it with the global client.
    klass.define_singleton_method(:parse) { |query| query }
    Object.const_set(name, klass)
    klass.single_instance(true) if single
    klass.fallback_locale(fallback) if fallback
    klass
  end

  def test_regional_aliases_enum_values_and_fallback_use_graphql_names
    klass = build_query(:RegionalPageQuery, fallback: "en-US")
    klass.graphql_fields(:id, :title)

    index = klass::INDEX
    assert_includes index, "en_US_items: allRegionalPages(locale: en_US, fallbackLocales: [en_US]"
    assert_includes index, "fr_items: allRegionalPages(locale: fr, fallbackLocales: [en_US]"
    refute_includes index, "en-US_items"
    GraphQL.parse(index)

    single = build_query(:RegionalGlobalQuery, single: true)
    single.graphql_fields(:id)
    assert_includes single::SINGLE, "en_US_item: regionalGlobal(locale: en_US"
    refute_includes single::SINGLE, "en-US_item"
    GraphQL.parse(single::SINGLE)
  end

  def test_localized_attributes_find_the_normalized_alias
    klass = build_query(:RegionalPageQuery)
    klass.graphql_fields(:id, :title)
    page = klass.new({"en_US_item" => {"id" => "1", "title" => "Bonjour"}})

    assert_equal "Bonjour", page.title
    assert_equal({"id" => "1", "title" => "Bonjour"}, page.localized_raw_attributes)
  end

  def test_sync_source_reads_normalized_response_keys_and_keeps_the_manifest_locale
    with_site(generated: false, queries: ["Page"]) do |root, data|
      manifest = ParademCmsSite::Manifest.new(data.merge(
        "locales" => ["en-US"], "locale_storage" => "string", "locale_mapping" => {"en-US" => "en-US"}
      ), root: root)
      query = Class.new do
        const_set(:META_DATA, "count")
        const_set(:INDEX, "index")
        def self.query_name = "Page"
        def self.single_instance? = false
        def self.graphql_page_size = 10
        def self.render? = true
      end
      client = Client.new({"en_US_items" => [{"id" => "cms-1", "permalink" => "sample"}]})
      source = ParademCmsSite::Sync::PublishedSource.new(manifest: manifest, queries: [query], client: client, concurrency: 1)

      rows = source.fetch
      assert_equal [["Page", "en-US", "cms-1"]], rows.map { |row| [row[:type], row[:locale], row[:cms_id]] }
      assert_equal "sample", rows.first[:permalink]
    end
  end
end
