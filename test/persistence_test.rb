require "test_helper"
require "active_record"
require "i18n"
require_relative "../lib/dato_cms_graphql/rails/cache_table"
require_relative "../lib/dato_cms_graphql/rails/persistence"

class PersistenceTest < Minitest::Test
  Payload = Struct.new(:id, :localized_raw_attributes) do
    def permalink
      localized_raw_attributes.fetch("slug")
    end
  end

  def setup
    @previous_locales = I18n.available_locales
    @previous_queries = DatoCmsGraphql.instance_variable_get(:@queries)
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
  end

  def teardown
    [:SyntheticPage, :SyntheticGlobal, :SyntheticCacheRecord].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
    ActiveRecord::Base.connection_pool.disconnect!
    DatoCmsGraphql.instance_variable_set(:@queries, @previous_queries)
    I18n.available_locales = @previous_locales
  end

  {
    "string_codes" => {locales: [:en, :fr], mapping: nil},
    "canada_and_cbns_integers" => {locales: [:fr, :en], mapping: {en: 0, fr: 1}},
    "afnan_english_integer" => {locales: [:en], mapping: {en: 0}}
  }.each do |name, configuration|
    define_method(:"test_#{name}_round_trip_updates_and_sti_projection") do
      configure_cache(**configuration)
      queries = [query("SyntheticPage", single: false), query("SyntheticGlobal", single: true)]
      DatoCmsGraphql.instance_variable_set(:@queries, queries)
      expected_ids = Set.new(queries.map(&:query_name))

      assert_equal expected_ids, DatoCmsGraphql::Rails::Persistence.cache_data
      rows = SyntheticCacheRecord.order(:id).to_a
      assert_equal configuration.fetch(:locales).size * 2, rows.size
      original_ids = rows.map(&:id)
      rows.each do |row|
        expected_storage = configuration[:mapping] ? configuration.fetch(:mapping).fetch(row.locale.to_sym) : row.locale
        assert_equal expected_storage, row.locale_before_type_cast
        assert_equal row.type, row.cms_id
        assert_equal "#{row.locale}-#{row.type.downcase}", row.permalink
        assert_equal row.permalink, row.cms_record.slug
        assert_equal "Original #{row.locale}", row.cms_record.title
        assert row.render?
        assert row.public_send(:"#{row.locale}?")
        assert_equal 1, row.class.where(locale: row.locale).count
      end
      assert_nil DatoCmsGraphql::Rails::Persistence.instance_variable_get(:@synced_ids)

      queries.each { |item| item.define_singleton_method(:title_prefix) { "Updated" } }
      next_ids = DatoCmsGraphql::Rails::Persistence.cache_data
      assert_equal expected_ids, next_ids
      refute_same expected_ids, next_ids
      assert_equal original_ids, SyntheticCacheRecord.order(:id).pluck(:id)
      SyntheticCacheRecord.all.each { |row| assert_equal "Updated #{row.locale}", row.cms_record.title }
    end
  end

  def test_failed_legacy_persistence_clears_tracking_and_restores_the_locale
    configure_cache(locales: [:en, :fr], mapping: {en: 0, fr: 1})
    successful = query("SyntheticPage", single: false)
    broken = query("SyntheticGlobal", single: true)
    broken.define_singleton_method(:get) { raise IOError, "Synthetic provider failure" }
    DatoCmsGraphql.instance_variable_set(:@queries, [successful, broken])
    previous_locale = I18n.locale
    assert_raises(IOError) { DatoCmsGraphql::Rails::Persistence.cache_data }
    assert_nil DatoCmsGraphql::Rails::Persistence.instance_variable_get(:@synced_ids)
    assert_equal previous_locale, I18n.locale

    DatoCmsGraphql.instance_variable_set(:@queries, [query("SyntheticGlobal", single: true)])
    assert_equal Set["SyntheticGlobal"], DatoCmsGraphql::Rails::Persistence.cache_data
  end

  def test_projection_tracks_assignment_and_active_record_write_paths
    configure_cache(locales: [:en, :fr], mapping: {en: 0, fr: 1})
    row = SyntheticPage.create!(locale: :en, cms_record: {"title" => "Original"})
    projection = row.cms_record
    assert_same projection, row.cms_record

    row.cms_record = {"title" => "Assigned"}
    assert_equal "Assigned", row.title
    refute_same projection, row.cms_record

    row[:cms_record] = {"title" => "Bracket assignment"}
    assert_equal "Bracket assignment", row.title
    row.write_attribute(:cms_record, {"title" => "Attribute write"})
    assert_equal "Attribute write", row.title
    row.update!(cms_record: {"title" => "Updated"})
    assert_equal "Updated", row.title
    row.update_columns(cms_record: {"title" => "Direct update"})
    assert_equal "Direct update", row.title
    assert_same row.cms_record, row.cms_record
  end

  def test_projection_refreshes_on_reload_and_is_not_shared_by_a_duplicate
    configure_cache(locales: [:en], mapping: nil)
    row = SyntheticPage.create!(locale: :en, cms_record: {"title" => "Original"})
    assert_equal "Original", row.title
    SyntheticPage.find(row.id).update!(cms_record: {"title" => "From database"})
    assert_equal "Original", row.title
    assert_equal "From database", row.reload.title

    row.cms_record.title = "Presentation-only change"
    assert_equal "From database", row.reload.title
    duplicate = row.dup
    refute_same row.cms_record, duplicate.cms_record
    duplicate.cms_record.title = "Duplicate only"
    assert_equal "From database", row.title
    assert_equal "Duplicate only", duplicate.title
  end

  def test_projection_detects_in_place_nested_json_edits_and_field_removal
    configure_cache(locales: [:en], mapping: nil)
    row = SyntheticPage.new(locale: :en, cms_record: {"title" => "Original", "cover" => {"alt" => "Before"}, "tags" => ["first"]})
    assert_equal "Before", row.cover.alt
    assert row.respond_to?(:title)
    row[:cms_record].fetch("cover").fetch("alt").replace("After")
    assert_equal "After", row.cover.alt
    row[:cms_record].fetch("tags") << "second"
    assert_equal %w[first second], row.tags
    row[:cms_record].delete("title")
    refute row.respond_to?(:title)
    assert_raises(NoMethodError) { row.title }
  end

  def test_projection_can_transition_between_nil_empty_and_present_payloads
    configure_cache(locales: [:en], mapping: nil)
    row = SyntheticPage.new(locale: :en, cms_record: nil)
    assert_nil row.cms_record
    row.cms_record = {}
    assert_instance_of OpenStruct, row.cms_record
    assert_same row.cms_record, row.cms_record
    row.cms_record = {"title" => "Present"}
    assert_equal "Present", row.title
    row.cms_record = nil
    assert_nil row.cms_record
    refute row.respond_to?(:title)
  end

  private

  def configure_cache(locales:, mapping:)
    I18n.available_locales = locales
    ActiveRecord::Base.connection.create_table(:synthetic_cache_records) do |table|
      table.string :type
      table.string :cms_id
      mapping ? table.integer(:locale) : table.string(:locale)
      table.boolean :render
      table.string :permalink
      table.json :cms_record
    end
    base = Object.const_set(:SyntheticCacheRecord, Class.new(ActiveRecord::Base))
    base.define_singleton_method(:dato_cms_locale_mapping) { mapping } if mapping
    base.include(DatoCmsGraphql::Rails::CacheTable)
    Object.const_set(:SyntheticPage, Class.new(base))
    Object.const_set(:SyntheticGlobal, Class.new(base))
  end

  def query(name, single:)
    Class.new do
      define_singleton_method(:query_name) { name }
      define_singleton_method(:single_instance?) { single }
      define_singleton_method(:render?) { true }
      define_singleton_method(:title_prefix) { "Original" }
      define_singleton_method(:get) do
        Payload.new(name, {"id" => name, "slug" => "#{I18n.locale}-#{name.downcase}", "title" => "#{title_prefix} #{I18n.locale}"})
      end
      define_singleton_method(:all) { [get] }
    end
  end
end
