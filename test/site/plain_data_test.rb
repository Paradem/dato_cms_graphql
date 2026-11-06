# frozen_string_literal: true

require "test_helper"

class PlainDataTest < Minitest::Test
  def test_normalizes_nested_opens_structs_without_mutating_them
    source = OpenStruct.new(images: [OpenStruct.new(url: "https://example.invalid/image", focal_point: OpenStruct.new(x: 0.2, y: 0.7))])
    result = ParademCmsSite::PlainData.call(source)
    assert_equal({"images" => [{"url" => "https://example.invalid/image", "focal_point" => {"x" => 0.2, "y" => 0.7}}]}, result)
    result["images"].first["url"].replace("changed")
    assert_equal "https://example.invalid/image", source.images.first.url
    assert_instance_of OpenStruct, source.images.first.focal_point
  end

  def test_rejects_duplicate_keys_cycles_nonfinite_numbers_and_unsupported_values
    cyclic = []
    cyclic << cyclic
    [{:id => "one", "id" => "two"}, cyclic, Float::INFINITY, Object.new].each do |value|
      assert_raises(ArgumentError) { ParademCmsSite::PlainData.call(value) }
    end
    circular = OpenStruct.new
    circular.self = circular
    assert_raises(ArgumentError) { ParademCmsSite::PlainData.call(circular) }
  end

  def test_shared_noncyclic_references_are_allowed
    shared = {id: "shared"}
    assert_equal [{"id" => "shared"}, {"id" => "shared"}], ParademCmsSite::PlainData.call([shared, shared])
  end
end
