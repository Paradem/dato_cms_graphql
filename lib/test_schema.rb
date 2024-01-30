## I'm stuck here making the mock - int type isn't defined on my schema ???

class PersonType < GraphQL::Schema::Object
  field :id, String, null: true
  field :name, String, null: true
end

class MetaType < GraphQL::Schema::Object
  field :count, Int, null: false
end

class QueryType < GraphQL::Schema::Object
  field :_all_under_tests_meta, MetaType, null: false
  def _all_under_tests_meta
    OpenStruct.new(
      count: 10
    )
  end

  field :all_under_tests, PersonType, null: false do
    argument :skip, Int, required: false
    argument :first, Int, required: false
  end

  def all_under_tests
    OpenStruct.new(
      id: "test",
      name: "Stan"
    )
  end
end

class TestSchema < GraphQL::Schema
  query(QueryType)
  def self.resolve_type(_type, obj, _ctx)
    obj.type
  end
end
