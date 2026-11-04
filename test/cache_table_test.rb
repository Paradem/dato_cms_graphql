require "test_helper"
require "i18n"
require_relative "../lib/dato_cms_graphql/rails/cache_table"

class CacheTableTest < Minitest::Test
  def setup
    @previous_locales = I18n.available_locales
  end

  def teardown
    I18n.available_locales = @previous_locales
  end

  def fake_base
    Class.new do
      class << self
        attr_reader :enum_calls

        def enum(name, values = nil, **options)
          (@enum_calls ||= []) << [name.to_s, values, options]
        end
      end
    end
  end

  def test_locale_enum_is_string_backed
    I18n.available_locales = [:en]
    klass = fake_base
    klass.include(DatoCmsGraphql::Rails::CacheTable)

    assert_equal [["locale", {"en" => "en"}, {}]], klass.enum_calls
  end

  def test_legacy_integer_mapping_does_not_follow_locale_order
    I18n.available_locales = [:fr, :en]
    klass = fake_base
    klass.define_singleton_method(:dato_cms_locale_mapping) { {en: 0, fr: 1} }
    klass.include(DatoCmsGraphql::Rails::CacheTable)

    assert_equal [["locale", {"en" => 0, "fr" => 1}, {}]], klass.enum_calls
  end

  def test_string_mapping_is_snapshotted_without_mutating_the_configuration
    I18n.available_locales = [:en]
    mapping = {en: +"en"}
    normalized = DatoCmsGraphql::Rails::CacheTable.validate_locale_mapping(mapping)
    mapping.fetch(:en).replace("changed")
    assert_equal({"en" => "en"}, normalized)
    assert normalized.frozen?
  end

  def test_legacy_single_locale_mapping
    I18n.available_locales = [:en]
    klass = fake_base
    klass.define_singleton_method(:dato_cms_locale_mapping) { {en: 0} }
    klass.include(DatoCmsGraphql::Rails::CacheTable)

    assert_equal [["locale", {"en" => 0}, {}]], klass.enum_calls
  end

  def test_incomplete_ambiguous_or_mixed_mappings_are_rejected_before_enum_definition
    I18n.available_locales = [:en, :fr]
    invalid = [nil, [], [:en, :fr], {}, {en: 0}, {en: 0, fr: 0}, {en: 0, fr: "fr"},
      {en: -1, fr: 1}, {en: "0", fr: "1"}, {en: "fr", fr: "en"}, {:en => 0, "en" => 1, :fr => 2}]
    invalid.each do |mapping|
      klass = fake_base
      klass.define_singleton_method(:dato_cms_locale_mapping) { mapping }
      assert_raises(ArgumentError, mapping.inspect) { klass.include(DatoCmsGraphql::Rails::CacheTable) }
      assert_nil klass.enum_calls
    end
  end

  def test_each_configured_locale_maps_to_its_own_string
    I18n.available_locales = [:en, :fr]
    klass = fake_base
    klass.include(DatoCmsGraphql::Rails::CacheTable)

    assert_equal [["locale", {"en" => "en", "fr" => "fr"}, {}]], klass.enum_calls
  end
end
