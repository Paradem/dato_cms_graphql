# frozen_string_literal: true

module DatoCmsGraphql
  class Fields
    attr_accessor :rv

    def initialize(fields)
      @fields = fields
      @rv = +""
    end

    def to_query
      @fields.each do |field|
        output_field(field, 0)
      end
      rv
    end

    def output_string(field, depth, key: false)
      indent = "  " * depth
      rv << indent
      rv << field.to_s[0] << field.to_s[1..].camelize(:lower)
      rv << "\n" unless key
    end

    def output_hash(field, rest, depth)
      output_string(field, depth, key: true)
      rv << " {\n"
      rest.each do |sub_field|
        output_field(sub_field, depth + 1)
      end
      rv << "  " * depth << "}\n"
    end

    def output_field(field, depth)
      if field.class.in?([Symbol, String])
        output_string(field, depth)
      elsif field.class.in?([Hash])
        field.each do |k, v|
          output_hash(k, v, depth)
        end
      end
    end
  end
end
