## [0.2.8] - 2025-12-17

- Add ostruct and logger as runtime dependencies for Ruby 3.4+ stdlib compatibility
- Update minitest to ~> 5.21 for better Ruby 3.4 support
- Update standardrb to ~> 1.52 for Ruby 3.4.5 linting support
- Fix literal string mutation in Fields class to avoid Ruby 3 warnings
- Update .standard.yml ruby_version to 3.4.5
- Resolve test warnings related to deprecated stdlib gems and string handling
- Enhanced AGENTS.md with targeted testing usage examples (e.g., commands for GraphQL field generation and path configuration tests) and a comprehensive "Using the Gem" guide, drawing from test suite patterns and README documentation for better developer onboarding
- Enhanced test suite with comprehensive edge case coverage for gem usage:
  - Error handling tests for API failures and invalid configurations
  - Boundary condition tests for field generation and data handling
  - Invalid input validation for queries and attributes
  - Concurrency tests for thread-safe query loading
  - Rails integration tests for caching, routing, and localization
- Added test dependencies: webmock, mocha, concurrent-ruby for mocking and simulation
- Improved gem reliability and developer confidence through test-demonstrated usage patterns

## [0.2.7] - 2025-12-17

## [0.1.0] - 2024-01-29

- Initial release
