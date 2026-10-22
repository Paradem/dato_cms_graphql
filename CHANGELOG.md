## [Unreleased]

## [0.4.1] - 2026-10-22

- Declare the CacheTable `locale` enum with string-backed keys and values so a
  string `records.locale` column round-trips readers, predicates and scopes
  instead of returning nil from Rails' default integer mapping for array enums.

## [0.1.0] - 2024-01-29

- Initial release
