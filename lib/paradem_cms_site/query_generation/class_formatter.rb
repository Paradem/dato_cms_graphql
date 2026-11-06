# frozen_string_literal: true

module ParademCmsSite::QueryGeneration
  class ClassFormatter
    def initialize(type_name, selection, single_instance: false, fallback_locale: nil, render: nil, base_class: "DatoCmsGraphql::BaseQuery")
      raise ArgumentError, "Invalid query model name" unless type_name.to_s.match?(ParademCmsSite::Manifest::MODEL_NAME)
      valid_fallback = fallback_locale.nil? || fallback_locale == :none || ((fallback_locale.is_a?(String) || fallback_locale.is_a?(Symbol)) && fallback_locale.to_s.match?(ParademCmsSite::Manifest::LOCALE))
      raise ArgumentError, "Invalid fallback locale" unless valid_fallback
      raise ArgumentError, "render must be boolean" unless [true, false, nil].include?(render)
      unless %w[DatoCmsGraphql::BaseQuery ParademCmsSite::Query].include?(base_class)
        raise ArgumentError, "Unsupported query base class"
      end
      @base_class = base_class
      @type_name = type_name
      @selection = selection
      @single_instance = single_instance
      @fallback_locale = fallback_locale
      @render = render
    end

    def to_s
      lines = ["# frozen_string_literal: true", ""]
      lines << "class #{type_name}Query < #{@base_class}"
      lines << indent(2) + "single_instance true" if single_instance
      # These directives must precede graphql_fields, which compiles constants.
      lines << indent(2) + "fallback_locale #{@fallback_locale.inspect}" unless @fallback_locale.nil?
      lines << indent(2) + "render #{@render.inspect}" unless @render.nil?
      lines << indent(2) + "graphql_fields("
      lines += formatted_selection
      lines << indent(2) + ")"
      lines << "end"
      lines.join("\n") + "\n"
    end

    private

    attr_reader :type_name, :selection, :single_instance

    def formatted_selection
      ordered = normalize_selection(selection)
      ordered.map { |item| format_array_element(item, 4) }
    end

    def format_array_element(item, indent_level)
      case item
      when Symbol
        indent(indent_level) + ":#{item},"
      when String
        indent(indent_level) + item.inspect + ","
      when Hash
        format_hash_entry(item, indent_level)
      else
        indent(indent_level) + item.to_s + ","
      end
    end

    def format_hash_entry(hash, indent_level)
      key, value = hash.first
      key_literal = key.is_a?(Symbol) ? "#{key}:" : "#{key.inspect}:"

      case value
      when Array
        nested = normalize_selection(value).map do |entry|
          format_array_element(entry, indent_level + 2)
        end
        [
          indent(indent_level) + key_literal + " [",
          *nested,
          indent(indent_level) + "],"
        ].join("\n")
      when Symbol
        indent(indent_level) + key_literal + " :#{value},"
      when String
        indent(indent_level) + key_literal + " #{value.inspect},"
      else
        indent(indent_level) + key_literal + " #{value},"
      end
    end

    def indent(count)
      " " * count
    end

    def normalize_selection(items)
      items = items.dup
      scalars, complex = items.partition { |item| scalar_item?(item) }
      scalars + complex
    end

    def scalar_item?(item)
      item.is_a?(Symbol) || item.is_a?(String)
    end
  end
end
