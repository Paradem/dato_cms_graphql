## [Unreleased]

## [0.4.2] - 2026-11-03

- Share `DatoCmsGraphql::HTTPTransport` between schema introspection and delivery,
  including explicit environment selection and per-request published/draft policy.
  Published requests omit `X-Include-Drafts`; the string `false` never enables drafts.
- Make the header policy independently loadable/testable without credentials,
  Rails boot or CMS networking; remove the need for BIC's local transport override.
- Use an explicit block parameter when requiring query files on Ruby 3.2/3.3.

## [0.4.1] - 2026-10-22

- Declare the CacheTable `locale` enum with string-backed keys and values so a
  string `records.locale` column round-trips readers, predicates and scopes
  instead of returning nil from Rails' default integer mapping for array enums.

## [0.1.0] - 2024-01-29

- Initial release
