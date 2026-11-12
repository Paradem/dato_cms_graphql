# frozen_string_literal: true

module DatoCmsGraphql
  # DatoCMS webhook/API locale codes may be hyphenated (en-GB), while GraphQL
  # enum values and aliases must be Names. Underscores are the one normalized
  # form shared by the DSL, installer, fixture resolver and sync source.
  module Locale
    PATTERN = /\A[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*\z/

    def self.graphql(value)
      value.to_s.tr("-", "_")
    end
  end
end
