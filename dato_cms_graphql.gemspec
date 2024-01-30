# frozen_string_literal: true

require_relative "lib/dato_cms_graphql/version"

Gem::Specification.new do |spec|
  spec.name = "dato_cms_graphql"
  spec.version = DatoCmsGraphql::VERSION
  spec.authors = ["Kevin Pratt"]
  spec.email = ["kevin@paradem.co"]

  spec.summary = "A basic library to assist in querying DatoCMS "
  spec.description = "This library allows you to generate models that can be used to query your DatoCMS instance."
  spec.homepage = "https://github.com/Paradem/dato_cms_graphql"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = ""

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Paradem/dato_cms_graphql.git"
  spec.metadata["changelog_uri"] = "https://github.com/Paradem/dato_cms_graphql.git/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  #
  spec.add_dependency "graphql-client", "~> 0.19.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
