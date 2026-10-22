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

  def test_each_configured_locale_maps_to_its_own_string
    I18n.available_locales = [:en, :fr]
    klass = fake_base
    klass.include(DatoCmsGraphql::Rails::CacheTable)

    assert_equal [["locale", {"en" => "en", "fr" => "fr"}, {}]], klass.enum_calls
  end
end
