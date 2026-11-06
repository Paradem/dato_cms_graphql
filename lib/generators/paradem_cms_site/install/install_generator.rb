# frozen_string_literal: true

require "rails/generators"
require "active_record"
require "yaml"
require "json"
require "paradem_cms_site"

module ParademCmsSite
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      class_option :site, type: :string, required: true, desc: "Stable website identifier"
      class_option :locales, type: :string, default: "en", desc: "Comma-separated CMS/UI locale codes"
      class_option :models, type: :string, default: "Page", desc: "Explicit owned model names"
      class_option :singletons, type: :string, default: "", desc: "Singleton models from the owned list"
      class_option :cache_model, type: :string, default: "CmsRecord"
      class_option :webhook, type: :string, default: "shared_header", desc: "shared_header, hmac_sha256 or disabled"
      class_option :fixture, type: :boolean, default: false, desc: "Install synthetic local schema/content for development/test"

      def install
        @models = split(options[:models])
        @locales = split(options[:locales])
        @singles = split(options[:singletons])
        validate_options!
        files = installation_files
        (@models + [options[:cache_model]]).each do |name|
          path = File.join(destination_root, "app/models/#{name.underscore}.rb")
          if Object.const_defined?(name, false) && !File.exist?(path)
            raise ::Rails::Generators::Error, "Model name #{name} collides with an existing constant"
          end
        end
        (files.keys + ["config/routes.rb"]).each { |path| check_destination!(path) }
        files.each do |relative, contents|
          path = File.join(destination_root, relative)
          if File.exist?(path) && (!File.file?(path) || File.binread(path) != contents)
            raise ::Rails::Generators::Error, "Refusing to overwrite #{relative}; review and merge the existing application file"
          end
        end
        routes = File.join(destination_root, "config/routes.rb")
        raise ::Rails::Generators::Error, "Run this generator inside a standard Rails application" unless File.file?(routes)
        route = 'post "webhooks/dato", to: "paradem_cms_site/webhooks#create"'
        if options[:webhook] != "disabled" && File.read(routes).include?("webhooks/dato") && !File.read(routes).include?(route)
          raise ::Rails::Generators::Error, "An existing /webhooks/dato route must be reviewed before installation"
        end
        files.each { |path, contents| create_file(path, contents) }
        route(route) if options[:webhook] != "disabled" && !File.read(routes).include?(route)
        say "Next: bin/rails db:migrate, bin/rails cms:doctor, then bin/rails cms:sync", :green
        say "Supply a local CDA GraphQL schema and runtime secrets; no CMS request or migration was run." unless options[:fixture]
      end

      private

      def split(value)
        value.split(",").map(&:strip).reject(&:empty?)
      end

      def validate_options!
        unless options[:site].match?(/\A[a-z][a-z0-9_-]*\z/)
          raise ::Rails::Generators::Error, "site must be a stable lowercase identifier"
        end
        unless @models.any? && @models.uniq == @models && @models.all? { |name| name.match?(Manifest::MODEL_NAME) && name.underscore.camelize == name }
          raise ::Rails::Generators::Error, "models must be unique model names"
        end
        unless @locales.any? && @locales.uniq == @locales && @locales.all? { |locale| locale.match?(/\A[a-z]{2,3}\z/) }
          raise ::Rails::Generators::Error, "Use unique simple GraphQL locale codes (for example en,fr); regional aliases need an explicit query adapter"
        end
        unless options[:cache_model].match?(Manifest::MODEL_NAME) && options[:cache_model].underscore.camelize == options[:cache_model] && !@models.include?(options[:cache_model]) && !%w[schema_migrations ar_internal_metadata].include?(options[:cache_model].tableize)
          raise ::Rails::Generators::Error, "cache_model must be a separate model name"
        end
        unless (@singles - @models).empty? && @singles.uniq == @singles
          raise ::Rails::Generators::Error, "singletons must belong to the owned model list"
        end
        unless %w[shared_header hmac_sha256 disabled].include?(options[:webhook])
          raise ::Rails::Generators::Error, "Unknown webhook strategy"
        end
      end

      def check_destination!(relative)
        root = Pathname(destination_root).realpath
        path = root.join(relative)
        path = path.parent until path.exist? || path.symlink?
        unless path.realpath == root || path.realpath.to_s.start_with?("#{root}/")
          raise ::Rails::Generators::Error, "Installation paths must stay inside the Rails application"
        end
      rescue Errno::ENOENT
        raise ::Rails::Generators::Error, "Dangling installation paths require review"
      end

      def installation_files
        cache = options[:cache_model]
        table = cache.tableize
        settings = {"cache_model" => cache, "delivery_schema" => "config/cms/schema.graphql", "webhook" => options[:webhook]}
        settings["fixture_data"] = "config/cms/fixture.json" if options[:fixture]
        manifest = {"version" => 1, "site" => options[:site], "locales" => @locales,
                    "locale_storage" => "string", "locale_mapping" => @locales.to_h { |locale| [locale, locale] },
                    "queries" => @models, "generated_queries" => false, "query_path" => "app/queries", "model_path" => "app/models", "rails" => settings}
        files = {
          "config/cms_site.yml" => YAML.dump(manifest),
          "config/initializers/paradem_cms_site.rb" => initializer,
          "app/models/#{cache.underscore}.rb" => "# frozen_string_literal: true\n\nclass #{cache} < ApplicationRecord\n  self.table_name = #{table.inspect}\n  include ParademCmsSite::CacheRecord\nend\n",
          migration_path(table) => migration(table)
        }
        @models.each do |name|
          files["app/models/#{name.underscore}.rb"] = "# frozen_string_literal: true\n\nclass #{name} < #{cache}\nend\n"
          directive = @singles.include?(name) ? "  single_instance true\n" : ""
          files["app/queries/#{name.underscore}_query.rb"] = "# frozen_string_literal: true\n\nclass #{name}Query < ParademCmsSite::Query\n#{directive}  graphql_fields(:id, :title, :permalink)\nend\n"
        end
        if options[:fixture]
          files[settings.fetch("delivery_schema")] = fixture_schema
          data = @models.to_h do |name|
            [name, @locales.to_h { |locale| [locale, [{"id" => "fixture-#{name.underscore}-#{locale}", "title" => "Synthetic #{name} (#{locale})", "permalink" => "#{locale}-#{name.underscore}"}]] }]
          end
          files[settings.fetch("fixture_data")] = JSON.pretty_generate(data) + "\n"
        end
        files
      end

      def initializer
        <<~RUBY
          # frozen_string_literal: true

          require "paradem_cms_site/rails/installation"

          Rails.application.config.to_prepare do
            ParademCmsSite::Installation.new(root: Rails.root).configure!
            ParademCmsSite.configure do |config|
              # Optional site-owned callbacks run with (result, context).
              # config.within_transaction = ->(result, context) { ... } # same DB only
              # config.after_sync = ->(result, context) { ... } # enqueue external work
              # config.webhook_context = ->(request) { {"webhook_log_id" => ...} }
            end
          end
        RUBY
      end

      def migration_path(table)
        existing = Dir[File.join(destination_root, "db/migrate/*_create_#{table}.rb")]
        raise ::Rails::Generators::Error, "Multiple CMS cache migrations require review" if existing.length > 1
        return Pathname(existing.first).relative_path_from(Pathname(destination_root)).to_s if existing.any?
        current = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
        latest = Dir[File.join(destination_root, "db/migrate/*.rb")].map { |path| File.basename(path).to_i }.max || 0
        "db/migrate/#{[current, latest + 1].max}_create_#{table}.rb"
      end

      def migration(table)
        <<~RUBY
          # frozen_string_literal: true

          class Create#{table.camelize} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
            def change
              create_table :#{table} do |t|
                t.string :type, null: false
                t.string :locale, null: false
                t.string :cms_id, null: false
                t.boolean :render, null: false, default: true
                t.string :permalink
                t.json :cms_record, null: false, default: {}
                t.timestamps
              end
              add_index :#{table}, [:type, :locale, :cms_id], unique: true
              add_index :#{table}, [:locale, :permalink]
            end
          end
        RUBY
      end

      def fixture_schema
        types = @models.map { |name| "type #{name}Record { id: ID!, title: String, permalink: String, _editingUrl: String, _seoMetaTags: [SeoTag!]! }" }
        fields = @models.flat_map do |name|
          if @singles.include?(name)
            ["#{name.camelize(:lower)}(locale: SiteLocale, fallbackLocales: [SiteLocale!]): #{name}Record"]
          else
            ["all#{name.pluralize}(locale: SiteLocale, fallbackLocales: [SiteLocale!], first: IntType, skip: IntType): [#{name}Record!]!", "_all#{name.pluralize}Meta: RecordMeta!"]
          end
        end
        "scalar IntType\nenum SiteLocale { #{@locales.join(" ")} }\ntype SeoTag { tag: String, content: String, attributes: String }\ntype RecordMeta { count: Int! }\n#{types.join("\n")}\ntype Query {\n  #{fields.join("\n  ")}\n}\n"
      end
    end
  end
end
