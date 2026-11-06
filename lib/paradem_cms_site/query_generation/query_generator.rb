# frozen_string_literal: true

require "fileutils"

module ParademCmsSite::QueryGeneration
  class QueryGenerator
    # Host tasks use this API directly; no host namespace or subclass is needed.
    # Path overrides do not replace the manifest's ownership/discriminator policy.
    def self.from_manifest(manifest, schema_path: nil, output_dir: nil, overrides_path: nil, model_dir: nil)
      raise ArgumentError, "This site uses hand-authored queries" unless manifest.generated_queries?

      new(
        schema_path: schema_path || manifest.path_for(:schema_export),
        output_dir: output_dir || manifest.path_for(:query_path),
        overrides_path: overrides_path || manifest.path_for(:overrides_path),
        model_dir: model_dir || manifest.path_for(:model_path),
        allowed_models: manifest.queries,
        model_api_key_selection: manifest.model_api_key_selection,
        query_base: manifest.data["rails"] ? "ParademCmsSite::Query" : "DatoCmsGraphql::BaseQuery",
        model_base: manifest.data.fetch("rails", {}).fetch("cache_model", "Record")
      )
    end

    def initialize(schema_path:, output_dir:, overrides_path:, model_dir:, allowed_models: nil, model_api_key_selection: :all,
      query_base: "DatoCmsGraphql::BaseQuery", model_base: "Record")
      raise ArgumentError, "Invalid cache model name" unless model_base.match?(ParademCmsSite::Manifest::MODEL_NAME)
      @query_base = query_base
      @model_base = model_base
      @schema = SchemaLoader.new(schema_path)
      @overrides = Overrides.load(overrides_path)
      @output_dir = output_dir
      @overrides_path = overrides_path
      @model_dir = model_dir
      @allowed_models = allowed_models
      @model_api_key_selection = model_api_key_selection
    end

    def generate(type_name, force: false, dry_run: false)
      name = type_name.to_s
      raise ArgumentError, "Invalid query model name" unless name.match?(ParademCmsSite::Manifest::MODEL_NAME)
      if @allowed_models && !@allowed_models.include?(name)
        raise ArgumentError, "Model is not owned by this site; update its manifest deliberately"
      end
      selection = SelectionBuilder.new(@schema, @overrides, model_api_key_selection: @model_api_key_selection).build(name)
      contents = ClassFormatter.new(name, selection,
        single_instance: @overrides.single_instance?(name),
        fallback_locale: @overrides.fallback_locale_for(name),
        render: @overrides.render_for(name), base_class: @query_base).to_s
      path = File.join(@output_dir, "#{underscore(name)}_query.rb")
      return {path: path, contents: contents} if dry_run

      raise IOError, "#{path} already exists. Pass FORCE=1 to overwrite." if File.exist?(path) && !force
      FileUtils.mkdir_p(@output_dir)
      File.write(path, contents)
      generate_model(name)
      @overrides.save!(@overrides_path)
      unless @overrides.new_link_fields.empty?
        puts "New link projections recorded in overrides; review their default id-only selections."
      end
      {path: path, contents: contents}
    end

    private

    def generate_model(type_name)
      path = File.join(@model_dir, "#{underscore(type_name)}.rb")
      return if File.exist?(path)
      FileUtils.mkdir_p(@model_dir)
      File.write(path, "# frozen_string_literal: true\n\nclass #{type_name} < #{@model_base}\nend\n")
    end

    def underscore(value)
      value.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
