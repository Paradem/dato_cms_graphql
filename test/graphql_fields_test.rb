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
        interview_location: [
          :latitude, :longitude
        ],
        featured_image: [
          colors: [:alpha]
        ]
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
end
