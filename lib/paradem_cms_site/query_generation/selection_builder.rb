# frozen_string_literal: true

module ParademCmsSite::QueryGeneration
  class SelectionBuilder
    DEFAULT_ASSET_SELECTION = [:url, :alt, :title, :width, :height, {focal_point: %i[x y]}].freeze
    DEFAULT_VIDEO_SELECTION = %i[url title provider provider_uid thumbnail_url height width].freeze
    DEFAULT_LINK_SELECTION = [:id].freeze
    DEFAULT_SEO_SELECTION = [:title, :description, :twitter_card, {image: DEFAULT_ASSET_SELECTION}].freeze
    SCALAR_TYPES = %w[string text integer float boolean slug date datetime json].freeze
    SKIPPED_FIELDS = %w[parent_id].freeze

    def initialize(schema, overrides = Overrides.new({}), model_api_key_selection: :all)
      unless %i[all blocks].include?(model_api_key_selection)
        raise ArgumentError, "model_api_key_selection must be all or blocks"
      end
      @schema = schema
      @overrides = overrides
      @model_api_key_selection = model_api_key_selection
    end

    def build(type_name)
      @overrides.custom_graphql_fields(type_name) || selection_for_type(type_name, [])
    end

    private

    def selection_for_type(type_name, visited)
      return [:id] if visited.include?(type_name)
      # Copy the ancestry: an early return from a cyclic branch must not pop
      # another branch's ancestor, as the old mutable ensure/pop implementation did.
      ancestry = visited + [type_name]
      definition = @schema.definition_for(type_name)
      entries = [:id]
      if @model_api_key_selection == :all || type_name.downcase.include?("block")
        entries << :_model_api_key
      end
      definition.fields.each do |field, attributes|
        selection = selection_for_field(type_name, field, attributes, ancestry)
        entries << selection if selection
      end
      (entries + @overrides.additional_fields_for(type_name)).uniq
    end

    def selection_for_field(type_name, field, attributes, visited)
      return if SKIPPED_FIELDS.include?(field) || @overrides.excluded_fields_for(type_name).include?(field)

      selection = case attributes["type"]
      when *SCALAR_TYPES
        field.to_sym
      when "file", "gallery"
        {field.to_sym => copy(DEFAULT_ASSET_SELECTION)}
      when "video"
        {field.to_sym => copy(DEFAULT_VIDEO_SELECTION)}
      when "link", "links"
        fields = @overrides.link_fields_for(type_name)&.dig(field.to_sym)
        unless fields
          fields = copy(DEFAULT_LINK_SELECTION)
          @overrides.add_link_field!(type_name, field, fields)
        end
        {field.to_sym => fields}
      when "seo"
        {field.to_sym => copy(DEFAULT_SEO_SELECTION)}
      when "rich_text"
        types = block_types(attributes["blocks"])
        raise ArgumentError, "Field '#{field}' has no valid block types" if types.empty?
        {field.to_sym => types.map { |type| fragment_selection_for(type, visited) }}
      when "structured_text"
        build_structured_text_selection(type_name, field, attributes, visited)
      when "lat_lon", "latlong"
        {field.to_sym => %i[latitude longitude]}
      else
        field.to_sym
      end

      alias_name = @overrides.field_alias_for(type_name, field)
      return selection unless alias_name
      unless alias_name.to_s.match?(/\A[_A-Za-z][_0-9A-Za-z]*\z/)
        raise ArgumentError, "Invalid GraphQL alias"
      end
      name = "#{alias_name}: #{field}"
      selection.is_a?(Hash) ? {name => selection.values.first} : name
    end

    def build_structured_text_selection(type_name, field, attributes, visited)
      selection = [:value]
      %w[blocks inline_blocks].each do |kind|
        types = block_types(attributes[kind])
        selection << {kind.to_sym => types.map { |type| fragment_selection_for(type, visited) }} unless types.empty?
      end
      links = @overrides.structured_text_links_for(type_name, field)
      selection << {links: links} unless links.empty?
      {field.to_sym => selection}
    end

    def fragment_selection_for(type_name, visited)
      {"... on #{type_name}Record" => selection_for_type(type_name, visited)}
    end

    def block_types(value)
      Array(value).flatten.compact.reject { |type| type == "never" }
    end

    def copy(value)
      case value
      when Array then value.map { |item| copy(item) }
      when Hash then value.transform_values { |item| copy(item) }
      else value
      end
    end
  end
end
