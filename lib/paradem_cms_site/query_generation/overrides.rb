# frozen_string_literal: true

require "yaml"

module ParademCmsSite::QueryGeneration
  class Overrides
    KEYS = %i[single_instance graphql_fields additional_fields excluded_fields exclude_fields field_aliases structured_text_links link_fields fallback_locale render].freeze

    def self.load(path)
      data = File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) : {}
      new(data || {})
    rescue Psych::Exception
      raise ArgumentError, "Invalid query override YAML"
    end

    def initialize(raw_data)
      raise ArgumentError, "Query overrides must be a mapping" unless raw_data.is_a?(Hash)
      @data = normalize_hash(raw_data, symbolize_keys: false)
      validate!
    end

    def single_instance?(type_name)
      !!overrides_for(type_name)[:single_instance]
    end

    def custom_graphql_fields(type_name)
      overrides_for(type_name)[:graphql_fields]
    end

    def additional_fields_for(type_name)
      overrides_for(type_name).fetch(:additional_fields, [])
    end

    # Keep both historical spellings, but reject ambiguous dual configuration.
    def excluded_fields_for(type_name)
      entry = overrides_for(type_name)
      Array(entry[:excluded_fields] || entry[:exclude_fields]).map(&:to_s)
    end

    def field_alias_for(type_name, field_name)
      overrides_for(type_name).dig(:field_aliases, field_name.to_sym)
    end

    # BIC uses raw fragments; Canada uses a model => fields mapping.
    def structured_text_links_for(type_name, field_name)
      links = overrides_for(type_name).dig(:structured_text_links, field_name.to_sym)
      case links
      when Hash
        links.map { |type, fields| {"... on #{type}Record" => fields} }
      when Array
        links
      else
        []
      end
    end

    def link_fields_for(type_name)
      overrides_for(type_name)[:link_fields]
    end

    def fallback_locale_for(type_name)
      overrides_for(type_name)[:fallback_locale]
    end

    def render_for(type_name)
      overrides_for(type_name)[:render]
    end

    def add_link_field!(type_name, field_name, default_fields)
      entry = @data[type_name.to_s] ||= {}
      links = entry[:link_fields] ||= {}
      return if links.key?(field_name.to_sym)

      links[field_name.to_sym] = default_fields
      new_link_fields << {type_name: type_name, field_name: field_name, fields: default_fields}
    end

    def new_link_fields
      @new_link_fields ||= []
    end

    def save!(path)
      return if new_link_fields.empty?
      File.write(path, YAML.dump(@data, aliases: false))
    end

    private

    def overrides_for(type_name)
      @data.fetch(type_name.to_s, {})
    end

    def validate!
      @data.each do |model, entry|
        unless model.match?(ParademCmsSite::Manifest::MODEL_NAME) && entry.is_a?(Hash)
          raise ArgumentError, "Override entries must map model names to options"
        end
        unknown = entry.keys - KEYS
        raise ArgumentError, "Unknown override keys for #{model}: #{unknown.join(", ")}" unless unknown.empty?
        if entry.key?(:excluded_fields) && entry.key?(:exclude_fields)
          raise ArgumentError, "Use one field-exclusion spelling for #{model}"
        end
        %i[single_instance render].each do |key|
          if entry.key?(key) && ![true, false].include?(entry[key])
            raise ArgumentError, "#{model}.#{key} must be boolean"
          end
        end
        if entry.key?(:fallback_locale)
          value = entry[:fallback_locale]
          valid = value == :none || ((value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.match?(ParademCmsSite::Manifest::LOCALE))
          raise ArgumentError, "Invalid fallback locale for #{model}" unless valid
        end
        %i[graphql_fields additional_fields excluded_fields exclude_fields].each do |key|
          if entry.key?(key) && !entry[key].is_a?(Array)
            raise ArgumentError, "#{model}.#{key} must be an array"
          end
        end
        %i[field_aliases link_fields structured_text_links].each do |key|
          if entry.key?(key) && !entry[key].is_a?(Hash)
            raise ArgumentError, "#{model}.#{key} must be a mapping"
          end
        end
        %i[excluded_fields exclude_fields].each do |key|
          if entry.key?(key) && !entry[key].all? { |field| field.is_a?(String) || field.is_a?(Symbol) }
            raise ArgumentError, "#{model}.#{key} must contain field names"
          end
        end
        unless entry.fetch(:field_aliases, {}).values.all? { |value| value.is_a?(String) || value.is_a?(Symbol) }
          raise ArgumentError, "#{model}.field_aliases must contain alias names"
        end
        entry.fetch(:link_fields, {}).each_value { |fields| validate_selection!(fields) }
        %i[graphql_fields additional_fields].each do |key|
          validate_selection!(entry[key]) if entry.key?(key)
        end
        entry.fetch(:structured_text_links, {}).each_value do |links|
          if links.is_a?(Hash)
            links.each do |type, fields|
              raise ArgumentError, "Invalid Structured Text linked model" unless type.to_s.match?(ParademCmsSite::Manifest::MODEL_NAME)
              validate_selection!(fields)
            end
          else
            validate_selection!(links)
          end
        end
      end
    end

    def validate_selection!(selection)
      raise ArgumentError, "GraphQL selections must be arrays" unless selection.is_a?(Array)
      selection.each do |item|
        case item
        when String, Symbol
          next
        when Hash
          raise ArgumentError, "A GraphQL selection entry must have one key" unless item.size == 1
          validate_selection!(item.values.first)
        else
          raise ArgumentError, "Unsupported GraphQL selection entry"
        end
      end
    end

    def normalize_hash(hash, symbolize_keys: true, ancestors: [])
      raise ArgumentError, "Cyclic query overrides are not supported" if ancestors.include?(hash.object_id)
      ancestors += [hash.object_id]
      hash.each_with_object({}) do |(key, value), result|
        name = key.to_s
        name = name.to_sym if symbolize_keys && name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        raise ArgumentError, "Duplicate normalized override key" if result.key?(name)
        result[name] = normalize_value(value, ancestors)
      end
    end

    def normalize_value(value, ancestors)
      case value
      when Hash
        normalize_hash(value, ancestors: ancestors)
      when Array
        raise ArgumentError, "Cyclic query overrides are not supported" if ancestors.include?(value.object_id)
        value.map { |item| normalize_value(item, ancestors + [value.object_id]) }
      when String
        (value.start_with?(":") && value.length > 1) ? value.delete_prefix(":").to_sym : value
      else
        value
      end
    end
  end
end
