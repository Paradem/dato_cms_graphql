require "test_helper"

class ReadmeExampleTest < Minitest::Test
  def test_documented_basic_query_example_compiles_and_enumerates_offline
    readme = File.read(File.expand_path("../README.md", __dir__))
    example = readme[/^class NewsQuery < DatoCmsGraphql::BaseQuery\n.*?^end$/m]
    refute_nil example, "README must document the BaseQuery collection example"
    refute_match(/GrapqlBase/, readme)

    TOPLEVEL_BINDING.eval(example)
    assert_equal "News", NewsQuery.query_name
    assert_equal ["synthetic-news"], I18n.with_locale(:en) { NewsQuery.all.map(&:id) }
  ensure
    Object.send(:remove_const, :NewsQuery) if Object.const_defined?(:NewsQuery, false)
  end
end
