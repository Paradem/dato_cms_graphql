class TestSchema < GraphQL::Schema
  class IntTypeType < GraphQL::Schema::Scalar
    def self.coerce_input(value, ctx)
      value.to_i
    end

    def self.coerce_result(value, ctx)
      value.to_i
    end
  end

  class TagType < GraphQL::Schema::Object
    field :tag, String, null: true
    field :content, String, null: true
    field :attributes, String, null: true
  end

  class PersonType < GraphQL::Schema::Object
    field :id, String, null: true
    field :name, String, null: true
    field :_seo_meta_tags, [TagType], null: false
  end

  class MetaType < GraphQL::Schema::Object
    field :count, IntTypeType, null: false
  end

  class Locale < GraphQL::Schema::Enum
    value "en", "a enum for english"
  end

  class QueryType < GraphQL::Schema::Object
    field :int_type, IntTypeType, null: false

    field :_all_under_tests_meta, MetaType, null: false
    def _all_under_tests_meta
      OpenStruct.new(
        count: 10
      )
    end

    field :all_under_tests, PersonType, null: false do
      argument :skip, IntTypeType, required: false
      argument :locale, Locale, required: false
      argument :first, IntTypeType, required: false
      argument :fallback_locales, [Locale], required: false
    end

    def all_under_tests
      OpenStruct.new(
        id: "test",
        name: "Stan",
        _seo_meta_tags: []
      )
    end
  end

  query(QueryType)
  def self.resolve_type(_type, obj, _ctx)
    obj.type
  end
end
