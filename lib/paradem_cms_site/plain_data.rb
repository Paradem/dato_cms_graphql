# frozen_string_literal: true

require "ostruct"

module ParademCmsSite
  # Normalize at JSON/renderer/indexing boundaries; ordinary views may keep the
  # host's existing OpenStruct-backed field access. Never mutate the source.
  module PlainData
    def self.call(value, ancestors = [])
      if value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(OpenStruct)
        raise ArgumentError, "Cyclic content is not supported" if ancestors.include?(value.object_id)
        ancestors += [value.object_id]
      end

      case value
      when OpenStruct
        call(value.to_h, ancestors)
      when Hash
        value.each_with_object({}) do |(key, item), result|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise ArgumentError, "Content keys must be strings or symbols"
          end
          name = key.to_s.dup
          raise ArgumentError, "Duplicate normalized content key" if result.key?(name)
          result[name] = call(item, ancestors)
        end
      when Array
        value.map { |item| call(item, ancestors) }
      when String
        value.dup
      when Integer, TrueClass, FalseClass, NilClass
        value
      when Float
        raise ArgumentError, "Content numbers must be finite" unless value.finite?
        value
      else
        raise ArgumentError, "Unsupported content value type"
      end
    end

    def self.deep_freeze(value)
      case value
      when Hash
        value.each { |key, item|
          key.freeze
          deep_freeze(item)
        }
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
