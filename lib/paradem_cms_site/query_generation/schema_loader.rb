# frozen_string_literal: true

module ParademCmsSite::QueryGeneration
  # Parses the TypeScript schema file exported by the DatoCMS CLI and exposes
  # the ItemTypeDefinition structures in a Ruby-friendly format.
  class SchemaLoader
    Definition = Struct.new(:name, :api_key, :fields)

    def initialize(schema_path)
      @schema_path = schema_path
      @definitions = parse_file(File.read(schema_path))
    end

    attr_reader :definitions

    def definition_for(name)
      definitions[name] || raise(KeyError, "Unknown DatoCMS type: #{name}")
    end

    private

    attr_reader :schema_path

    def parse_file(content)
      defs = {}
      offset = 0
      pattern = /export type (?<name>\w+) = ItemTypeDefinition<[^,]+,\s*'(?<api_key>[^']+)',\s*\{/

      while (match = pattern.match(content, offset))
        name = match[:name]
        api_key = match[:api_key]
        body, index_after_body = extract_braced_content(content, match.end(0) - 1)
        fields = parse_fields(body[1...-1])
        defs[name] = Definition.new(name: name, api_key: api_key, fields: fields)
        offset = index_after_body
      end

      defs
    end

    def extract_braced_content(str, start_index)
      depth = 0
      i = start_index

      while i < str.length
        char = str[i]

        if char == "{"
          depth += 1
        elsif char == "}"
          depth -= 1
          return [str[start_index..i], i + 1] if depth.zero?
        end

        i += 1
      end

      raise ArgumentError, "Unbalanced braces while parsing #{schema_path}"
    end

    def parse_fields(body)
      fields = {}
      index = 0

      while index < body.length
        index = skip_whitespace(body, index)
        break if index >= body.length

        name_start = index
        index += 1 while index < body.length && identifier_char?(body[index])
        field_name = body[name_start...index]

        index = skip_whitespace(body, index)
        raise_parse_error("field delimiter", body, index) unless body[index] == ":"
        index += 1
        index = skip_whitespace(body, index)

        raise_parse_error("field body", body, index) if body[index] != "{"

        field_body, index = extract_braced_content(body, index)
        fields[field_name] = parse_field_attributes(field_body[1...-1])

        index = skip_field_terminator(body, index)
      end

      fields
    end

    def parse_field_attributes(body)
      attrs = {}
      index = 0

      while index < body.length
        index = skip_whitespace(body, index)
        break if index >= body.length

        key_start = index
        index += 1 while index < body.length && identifier_char?(body[index])
        key = body[key_start...index]

        index = skip_whitespace(body, index)
        raise_parse_error("attribute delimiter", body, index) unless body[index] == ":"
        index += 1
        index = skip_whitespace(body, index)

        value, index = parse_value(body, index)
        attrs[key] = value

        index = skip_whitespace(body, index)
        index = skip_field_terminator(body, index)
      end

      attrs
    end

    def parse_value(str, index)
      case str[index]
      when "'"
        parse_single_quoted(str, index)
      when "{"
        nested_body, next_index = extract_braced_content(str, index)
        [parse_field_attributes(nested_body[1...-1]), next_index]
      else
        parse_unquoted(str, index)
      end
    end

    def parse_single_quoted(str, index)
      closing = str.index("'", index + 1)
      raise_parse_error("closing quote", str, index) unless closing
      value = str[(index + 1)...closing]
      [value, closing + 1]
    end

    def parse_unquoted(str, index)
      value = +""
      while index < str.length && !terminator?(str[index])
        value << str[index]
        index += 1
      end
      value.strip!

      parsed = case value
      when ""
        nil
      when "true"
        true
      when "false"
        false
      else
        parse_unquoted_content(value)
      end

      [parsed, index]
    end

    def parse_unquoted_content(value)
      if value.include?("|")
        value.split("|").map { |part| part.strip }.reject(&:empty?)
      elsif value.match?(/\A-?\d+\z/)
        value.to_i
      elsif value.match?(/\A-?\d+\.\d+\z/)
        value.to_f
      elsif value.empty?
        nil
      else
        value
      end
    end

    def skip_field_terminator(str, index)
      index += 1 while index < str.length && [",", ";", "\n", "\r", "\t", " "].include?(str[index])
      index
    end

    def skip_whitespace(str, index)
      index += 1 while index < str.length && whitespace?(str[index])
      index
    end

    def whitespace?(char)
      [" ", "\t", "\n", "\r"].include?(char)
    end

    def terminator?(char)
      char.nil? || char == ";" || char == "," || char == "}"
    end

    def identifier_char?(char)
      return false unless char

      char.match?(/[A-Za-z0-9_]/)
    end

    def raise_parse_error(expected, str, index)
      snippet = str[[index - 20, 0].max, 40]
      raise ArgumentError, "Unable to parse #{schema_path}: expected #{expected} near '#{snippet}'"
    end
  end
end
