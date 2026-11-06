# frozen_string_literal: true

require_relative "lib/dato_cms_graphql/version"

Gem::Specification.new do |spec|
  spec.name = "dato_cms_graphql"
  spec.version = DatoCmsGraphql::VERSION
  spec.authors = ["Kevin Pratt"]
  spec.email = ["kevin@paradem.co"]

  spec.summary = "DatoCMS queries and optional Rails cache synchronization"
  spec.description = "Query DatoCMS with explicit transport policy, or opt into offline-first Rails installation, query generation, atomic cache refresh and authenticated webhooks."
  spec.homepage = "https://github.com/Paradem/dato_cms_graphql"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = ""

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Paradem/dato_cms_graphql.git"
  spec.metadata["changelog_uri"] = "https://github.com/Paradem/dato_cms_graphql.git/CHANGELOG.md"

  # Package only the public implementation and documentation, never local data,
  # credentials, planning files, tests or development dependency locks.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "exe/*", "docs/**/*.md", "sig/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
      .select { |path| File.file?(path) }.sort
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  #
  spec.add_dependency "graphql-client", "~> 0.23.0"
  spec.add_dependency "activesupport", ">= 7.1", "< 9.0"
  spec.add_dependency "ostruct"
  spec.add_dependency "logger"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
