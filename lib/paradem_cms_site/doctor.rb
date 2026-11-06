# frozen_string_literal: true

module ParademCmsSite
  # Read-only filesystem/configuration checks. Never load host query/model Ruby:
  # doing so could initialize the API client or encrypted Rails configuration.
  class Doctor
    def initialize(manifest)
      @manifest = manifest
    end

    def problems
      issues = []
      @manifest.queries.each do |model|
        issues << "Missing owned query: #{model}" unless @manifest.query_file_for(model).file?
        issues << "Missing owned model: #{model}" unless @manifest.model_file_for(model).file?
      end
      expected = @manifest.queries.map { |model| @manifest.query_file_for(model).to_s }
      actual = Dir[@manifest.path_for(:query_path).join("*_query.rb")].sort
      (actual - expected).each { |path| issues << "Unregistered query file: #{File.basename(path)}" }

      if (settings = @manifest.data["rails"])
        name = settings.fetch("cache_model").gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        issues << "Missing installed CMS cache model" unless @manifest.path_for(:model_path).join("#{name}.rb").file?
        issues << "Missing Rails CMS initializer" unless @manifest.root.join("config/initializers/paradem_cms_site.rb").file?
        unless @manifest.path_for(:delivery_schema).file? || settings.fetch("allow_schema_introspection", false)
          issues << "Supply the local GraphQL delivery schema: #{settings.fetch("delivery_schema")}"
        end
        fixture = @manifest.path_for(:fixture_data)
        issues << "Missing local CMS fixture data" if fixture && !fixture.file?
      end

      if @manifest.generated_queries?
        require_relative "query_generation"
        schema_path = @manifest.path_for(:schema_export)
        override_path = @manifest.path_for(:overrides_path)
        issues << "Missing schema export" unless schema_path.file?
        issues << "Missing query overrides" unless override_path.file?
        if schema_path.file? && override_path.file?
          schema = QueryGeneration::SchemaLoader.new(schema_path)
          QueryGeneration::Overrides.load(override_path)
          @manifest.queries.each do |model|
            issues << "Owned model absent from schema export: #{model}" unless schema.definitions.key?(model)
          end
        end
      end
      issues
    rescue ArgumentError, KeyError => error
      issues << "Invalid local query configuration: #{error.message}"
    end
  end
end
