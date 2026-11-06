# frozen_string_literal: true

require "pathname"
require "yaml"

module ParademCmsSite
  # Local, versioned ownership metadata. This is not a CMS credential, runtime
  # query registry, route declaration, or permission to mutate a remote project.
  class Manifest
    KEYS = %w[version site locales locale_storage locale_mapping queries generated_queries schema_export query_path model_path overrides_path model_api_key_selection permalink_fields optional_singletons rails].freeze
    MODEL_NAME = /\A[A-Z][A-Za-z0-9]*\z/
    LOCALE = /\A[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*\z/

    attr_reader :root, :data

    def self.load(root:, path: "config/cms_site.yml")
      base = Pathname(root).realpath
      location = base.join(path).cleanpath
      unless location.to_s.start_with?("#{base}/") && location.realpath.to_s.start_with?("#{base}/")
        raise ConfigurationError, "Manifest must be inside the site root"
      end
      new(YAML.safe_load_file(location, aliases: false), root: base)
    rescue Psych::Exception
      raise ConfigurationError, "Invalid manifest YAML"
    end

    def initialize(data, root:)
      @root = Pathname(root).realpath
      raise ConfigurationError, "Site root must be a directory" unless @root.directory?
      raise ConfigurationError, "Manifest must be a mapping" unless data.is_a?(Hash)
      @data = PlainData.call(data)
      validate!
      PlainData.deep_freeze(@data)
      @root.freeze
    end

    def site = data.fetch("site")
    def locales = data.fetch("locales")
    def queries = data.fetch("queries")
    def locale_storage = data.fetch("locale_storage")
    def locale_mapping = data.fetch("locale_mapping")
    def generated_queries? = data.fetch("generated_queries")
    def model_api_key_selection = data.fetch("model_api_key_selection", "all").to_sym
    def optional_singletons = data.fetch("optional_singletons", [])

    def path_for(key)
      relative = %w[delivery_schema fixture_data].include?(key.to_s) ? data.fetch("rails", {})[key.to_s] : data[key.to_s]
      return if relative.nil?
      unless relative.is_a?(String) && !relative.empty? && !relative.include?("\0")
        raise ConfigurationError, "#{key} must be a relative path"
      end
      path = Pathname(relative)
      if path.absolute? || path.each_filename.include?("..")
        raise ConfigurationError, "#{key} must stay inside the site root"
      end
      expanded = root.join(path).cleanpath
      existing = expanded
      existing = existing.parent until existing.exist? || existing.symlink?
      unless existing.realpath == root || existing.realpath.to_s.start_with?("#{root}/")
        raise ConfigurationError, "#{key} must not escape through a symlink"
      end
      expanded
    rescue Errno::ENOENT
      raise ConfigurationError, "#{key} contains a dangling path"
    end

    def query_file_for(model)
      owned_model!(model)
      path_for(:query_path).join("#{underscore(model)}_query.rb")
    end

    def model_file_for(model)
      owned_model!(model)
      path_for(:model_path).join("#{underscore(model)}.rb")
    end

    def identity_for(model, locale:, payload:)
      owned_model!(model)
      code = locale.to_s
      raise ConfigurationError, "Locale is not owned by this site" unless locales.include?(code)
      record = PlainData.call(payload)
      id = record["id"] if record.is_a?(Hash)
      unless id.is_a?(String) && !id.empty? && id == id.strip
        raise ConfigurationError, "CMS identity requires a nonblank string id"
      end
      [model.to_s, id, code]
    end

    def permalink_for(model, payload:)
      owned_model!(model)
      field = data.fetch("permalink_fields", {}).fetch(model.to_s, "permalink")
      record = PlainData.call(payload)
      raise ConfigurationError, "CMS projection requires a mapping" unless record.is_a?(Hash)
      value = record[field]
      unless value.nil? || value.is_a?(String)
        raise ConfigurationError, "CMS permalink must be a string or null"
      end
      value
    end

    private

    def validate!
      unknown = data.keys - KEYS
      raise ConfigurationError, "Unknown manifest keys: #{unknown.join(", ")}" unless unknown.empty?
      raise ConfigurationError, "Unsupported manifest version" unless data["version"] == 1
      unless data["site"].is_a?(String) && data["site"].match?(/\A[a-z][a-z0-9_-]*\z/)
        raise ConfigurationError, "site must be a stable lowercase identifier"
      end
      unless locales.is_a?(Array) && locales.any? && locales.uniq == locales && locales.all? { |locale| locale.is_a?(String) && locale.match?(LOCALE) }
        raise ConfigurationError, "locales must be unique locale codes"
      end
      unless queries.is_a?(Array) && queries.any? && queries.uniq == queries && queries.all? { |name| name.is_a?(String) && name.match?(MODEL_NAME) }
        raise ConfigurationError, "queries must be unique owned model names"
      end
      unless [true, false].include?(data["generated_queries"])
        raise ConfigurationError, "generated_queries must be explicit"
      end
      unless %w[string integer].include?(locale_storage)
        raise ConfigurationError, "locale_storage must be string or integer"
      end
      mapping = locale_mapping
      valid = mapping.is_a?(Hash) && mapping.keys.sort == locales.sort && mapping.values.uniq.size == locales.size
      valid &&= mapping.all? { |locale, value| (locale_storage == "string") ? value == locale : value.is_a?(Integer) && value >= 0 }
      raise ConfigurationError, "locale_mapping must explicitly match locale storage" unless valid
      unless %w[all blocks].include?(data.fetch("model_api_key_selection", "all"))
        raise ConfigurationError, "model_api_key_selection must be all or blocks"
      end
      projections = data.fetch("permalink_fields", {})
      unless projections.is_a?(Hash) && (projections.keys - queries).empty? && projections.values.all? { |value| value.is_a?(String) && value.match?(/\A[a-z][a-z0-9_]*\z/) }
        raise ConfigurationError, "permalink_fields must name fields on owned models"
      end
      optional = optional_singletons
      unless optional.is_a?(Array) && optional.uniq == optional && (optional - queries).empty?
        raise ConfigurationError, "optional_singletons must name unique owned queries"
      end
      %w[query_path model_path].each do |key|
        raise ConfigurationError, "#{key} is required" unless data[key]
        path_for(key)
      end
      if generated_queries?
        %w[schema_export overrides_path].each do |key|
          raise ConfigurationError, "#{key} is required for generated queries" unless data[key]
        end
      end
      %w[schema_export overrides_path].each { |key| path_for(key) }
      if data.key?("rails")
        settings = data.fetch("rails")
        unless settings.is_a?(Hash) && (settings.keys - %w[cache_model delivery_schema fixture_data webhook allow_schema_introspection boot_fallback]).empty?
          raise ConfigurationError, "Invalid Rails installation settings"
        end
        unless settings["cache_model"].is_a?(String) && settings["cache_model"].match?(MODEL_NAME) && !queries.include?(settings["cache_model"])
          raise ConfigurationError, "Rails cache_model must be a model name"
        end
        unless %w[shared_header hmac_sha256 disabled].include?(settings["webhook"])
          raise ConfigurationError, "Unknown webhook authentication strategy"
        end
        %w[allow_schema_introspection boot_fallback].each do |key|
          unless [true, false].include?(settings.fetch(key, false))
            raise ConfigurationError, "Rails #{key} must be a boolean"
          end
        end
        raise ConfigurationError, "Rails delivery_schema is required" unless settings["delivery_schema"]
        %w[delivery_schema fixture_data].each { |key| path_for(key) }
      end
    rescue KeyError
      raise ConfigurationError, "Manifest is missing required configuration"
    end

    def owned_model!(model)
      raise ConfigurationError, "Model is not owned by this site" unless queries.include?(model.to_s)
    end

    def underscore(value)
      value.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
