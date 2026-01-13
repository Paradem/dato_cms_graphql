require "test_helper"

class UnderTest < DatoCmsGraphql::BaseQuery
  graphql_fields(
    :id
  )
end

class GraphqlFieldsTest < Minitest::Test
  def test_field_generation
    fields =
      [
        :id, :title,
        :permalink, :_status,
        :_first_published_at,
        {interview_location: %i[latitude longitude],
         featured_image: [
           colors: [:alpha]
         ]}
      ]

    fields_str = <<~GRAPHQL
      id
      title
      permalink
      _status
      _firstPublishedAt
      interviewLocation {
        latitude
        longitude
      }
      featuredImage {
        colors {
          alpha
        }
      }
    GRAPHQL

    # puts Fields.new(fields).to_query

    assert_equal fields_str, DatoCmsGraphql::Fields.new(fields).to_query
    assert true
  end

  def test_hi_again
    attributes = {"id" => "aOgVuOkbTpKl56nHftl3FA"}

    portrait = UnderTest.new(attributes.deep_transform_keys { |k| k.underscore })

    assert_equal "aOgVuOkbTpKl56nHftl3FA", portrait.id
  end

  def test_field_generation_with_empty_fields
    fields = []
    assert_equal "", DatoCmsGraphql::Fields.new(fields).to_query
  end

  def test_field_generation_with_deep_nesting
    fields = [level1: [level2: [level3: [:deep_field]]]]
    expected = "level1 {\n  level2 {\n    level3 {\n      deepField\n    }\n  }\n}\n"
    assert_equal expected, DatoCmsGraphql::Fields.new(fields).to_query
  end

  def test_field_generation_with_invalid_types
    fields = 123
    assert_raises(NoMethodError) { DatoCmsGraphql::Fields.new(fields).to_query }
  end

  def test_field_generation_with_malformed_hash
    fields = [{invalid: "not_an_array"}]
    assert_raises(NoMethodError) { DatoCmsGraphql::Fields.new(fields).to_query }
  end

  def test_field_camelcase_conversion
    fields = [:_first_published_at]
    expected = "_firstPublishedAt\n"
    assert_equal expected, DatoCmsGraphql::Fields.new(fields).to_query
  end

  def test_field_generation_with_reserved_keywords
    fields = [:type]
    assert_equal "type\n", DatoCmsGraphql::Fields.new(fields).to_query
  end
end
