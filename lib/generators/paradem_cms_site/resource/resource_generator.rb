# frozen_string_literal: true

require "generators/paradem_cms_site/base"
require "paradem_cms_site/query_generation"
require "graphql"

module ParademCmsSite
  module Generators
    class ResourceGenerator < Base
      argument :name, type: :string, required: true
      class_option :singleton, type: :boolean, default: false
      class_option :body, type: :string, desc: "Optional plain-text starter field; rich text stays host-owned"
      class_option :permalink, type: :string, default: "permalink", desc: "CMS field projected to the cache permalink"
      class_option :fallback_locale, type: :string, desc: "Owned locale code or none"
      class_option :theme, type: :string, desc: "Previously generated theme shell"

      def generate_resource
        model_name!(name)
        require_view_component!
        @manifest = installed_manifest
        @singleton = options[:singleton]
        @fields = ["title", options[:permalink], options[:body]].compact
        unless @fields.uniq == @fields && @fields.all? { |field| field.match?(/\A[a-z][a-z0-9_]*\z/) && !%w[id type locale cms_record render].include?(field) }
          raise Error, "Use distinct, conventional title/permalink/body field names"
        end
        if options[:fallback_locale] && !(["none"] + @manifest.locales).include?(options[:fallback_locale])
          raise Error, "fallback_locale must be an owned locale or none"
        end
        if name == @manifest.data.fetch("rails").fetch("cache_model") || (Object.const_defined?(name, false) && !checked_path("app/models/#{name.underscore}.rb").file?)
          raise Error, "Resource name collides with an existing constant"
        end
        if options[:theme]
          unless options[:theme].match?(/\A[a-z][a-z0-9_]*\z/) && checked_path("app/views/layouts/site/#{options[:theme]}.html.erb").file?
            raise Error, "Generate the requested theme first"
          end
        end
        data = @manifest.data.deep_dup
        fresh = !data.fetch("queries").include?(name)
        data.fetch("queries") << name if fresh
        projections = data.fetch("permalink_fields", {})
        if !fresh && projections.fetch(name, "permalink") != options[:permalink]
          raise Error, "Existing permalink projection differs; review it explicitly"
        end
        if options[:permalink] != "permalink"
          data["permalink_fields"] = projections.merge(name => options[:permalink])
        end
        candidate = Manifest.new(data, root: destination_root)
        files = test_helper_files
        updates = {}
        managed = []
        files[candidate.model_file_for(name).relative_path_from(candidate.root).to_s] = model_source
        files[candidate.query_file_for(name).relative_path_from(candidate.root).to_s] = query_source(candidate)
        if data != @manifest.data
          updates["config/cms_site.yml"] = managed_contents("config/cms_site.yml")
          files["config/cms_site.yml"] = YAML.dump(data)
          managed << "config/cms_site.yml"
        end
        extend_fixture(candidate, files, updates, managed) if fresh && @manifest.path_for(:fixture_data)
        folder = name.tableize
        controller = name.pluralize
        route_name = "cms_#{name.underscore}"
        path = "cms/:locale/#{folder}#{"/:permalink" unless @singleton}"
        action = @singleton ? "      @record = #{name}.localized.where(render: true).first!" : "      @record = #{name}.localized.where(render: true).find_by!(permalink: params[:permalink])"
        files["app/controllers/site/#{folder}_controller.rb"] = localized_controller(controller, action, layout: options[:theme] && "site/#{options[:theme]}")
        files["app/components/site/#{name.underscore}_component.rb"] = component_source
        files[component_template("app/components/site/#{name.underscore}_component")] = component_view
        files["app/views/site/#{folder}/show.html.erb"] = "<%= render Site::#{name}Component.new(record: @record) %>\n"
        files["app/helpers/site/#{name.underscore}_helper.rb"] = helper_source(route_name)
        files["test/fixtures/files/cms_#{name.underscore}.json"] = JSON.pretty_generate(sample) + "\n"
        files["test/integration/cms_#{name.underscore}_test.rb"] = request_test(route_name)
        files["test/system/cms_#{name.underscore}_test.rb"] = system_test(route_name)
        files["test/components/site/#{name.underscore}_component_test.rb"] = component_test
        add_route(files, updates, %(get #{path.inspect}, to: "site/#{folder}#show", as: :#{route_name}), key: "resource:#{name}", marker: "cms/:locale/#{folder}", route_name: route_name)
        parameters = options.to_h.slice(*%w[singleton body permalink fallback_locale theme])
        write_scaffold("resource:#{name}", parameters, files, updates: updates, managed: managed)
        say "Review /#{path}, the host-owned query/component/path helper and required tests. No CMS request or migration was run.", :green
      end

      private

      def model_source
        "# frozen_string_literal: true\n\nclass #{name} < #{@manifest.data.fetch("rails").fetch("cache_model")}\nend\n"
      end

      def query_source(manifest)
        if manifest.generated_queries?
          overrides = QueryGeneration::Overrides.load(manifest.path_for(:overrides_path))
          matching_singleton = overrides.single_instance?(name) == @singleton
          matching_fallback = !options[:fallback_locale] || overrides.fallback_locale_for(name).to_s == options[:fallback_locale]
          unless matching_singleton && matching_fallback
            raise Error, "Prepare matching singleton/fallback overrides before generating this resource"
          end
          schema = QueryGeneration::SchemaLoader.new(manifest.path_for(:schema_export))
          schema.definition_for(name)
          selection = QueryGeneration::SelectionBuilder.new(schema, overrides, model_api_key_selection: manifest.model_api_key_selection).build(name)
          projected_fields = selection.reject { |field| field.is_a?(Hash) }.map { |field| field.to_s.split(":", 2).first.strip }
          unless (@fields - projected_fields).empty?
            raise Error, "The starter needs selected scalar title/body/permalink projections; review query overrides or supply a host renderer"
          end
          return QueryGeneration::QueryGenerator.from_manifest(manifest).generate(name, dry_run: true).fetch(:contents)
        end
        directives = @singleton ? "  single_instance true\n" : ""
        if options[:fallback_locale]
          value = (options[:fallback_locale] == "none") ? ":none" : options[:fallback_locale].inspect
          directives += "  fallback_locale #{value}\n"
        end
        fields = (["id"] + @fields).map { |field| ":#{field}" }.join(", ")
        "# frozen_string_literal: true\n\nclass #{name}Query < ParademCmsSite::Query\n#{directives}  graphql_fields(#{fields})\nend\n"
      end

      def extend_fixture(candidate, files, updates, managed)
        schema = @manifest.path_for(:delivery_schema).relative_path_from(@manifest.root).to_s
        fixture = @manifest.path_for(:fixture_data).relative_path_from(@manifest.root).to_s
        unless File.extname(schema) == ".graphql"
          raise Error, "Only generated synthetic SDL can be extended; review real schema changes separately"
        end
        old = managed_contents(schema)
        definition = "#{old}\n#{fixture_type(name, @fields)}\nextend type Query {\n  #{fixture_query_fields(name, singleton: @singleton).join("\n  ")}\n}\n"
        GraphQL::Schema.from_definition(definition)
        rows = JSON.parse(managed_contents(fixture))
        rows[name] = candidate.locales.to_h do |locale|
          payload = sample.merge("id" => "fixture-#{name.underscore}-#{locale}", "title" => "Synthetic #{name} (#{locale})", options[:permalink] => "#{locale}-#{name.underscore}")
          [locale, [payload]]
        end
        updates[schema] = old
        updates[fixture] = managed_contents(fixture)
        files[schema] = definition
        files[fixture] = JSON.pretty_generate(rows) + "\n"
        managed.concat([schema, fixture])
      end

      def sample
        value = {"id" => "synthetic-#{name.underscore}", "title" => "Synthetic #{name}", options[:permalink] => "synthetic-#{name.underscore}"}
        value[options[:body]] = "Synthetic plain-text body." if options[:body]
        value
      end

      def component_source
        <<~RUBY
          # frozen_string_literal: true

          module Site
            class #{name}Component < ViewComponent::Base
              def initialize(record:)
                @record = record
              end
            end
          end
        RUBY
      end

      def component_view
        html = "<article class=\"mx-auto max-w-3xl px-6 py-12\">\n  <h1 class=\"font-site-heading text-3xl\"><%= @record.title.presence || @record.class.model_name.human %></h1>\n"
        html += "  <p class=\"mt-6\"><%= @record[:cms_record][#{options[:body].inspect}] %></p>\n" if options[:body]
        html + "</article>\n"
      end

      def helper_source(route_name)
        arguments = @singleton ? "locale: locale" : "locale: locale, permalink: record.permalink"
        <<~RUBY
          # frozen_string_literal: true

          module Site
            module #{name}Helper
              # Keep domain-specific path projection here, not in a shared renderer.
              def #{route_name}_path_for(record, locale: record.locale)
                #{route_name}_path(#{arguments})
              end
            end
          end
        RUBY
      end

      def request_test(route_name)
        arguments = @singleton ? "locale: locale" : 'locale: locale, permalink: "synthetic-path"'
        <<~RUBY
          require "test_helper"

          class Cms#{name}Test < ActionDispatch::IntegrationTest
            test "owned locales render synthetic content and invalid locales fail closed" do
              payload = JSON.parse(file_fixture("cms_#{name.underscore}.json").read)
              ParademCmsSite.configuration.installation.manifest.locales.each do |locale|
                #{name}.where(locale: locale).delete_all
                record = #{name}.create!(cms_id: "cms-resource-test", locale: locale, render: true, permalink: "synthetic-path", cms_record: payload)
                get #{route_name}_path(#{arguments})
                assert_response :success
                assert_select "h1", payload.fetch("title")
                record.update!(render: false)
                get #{route_name}_path(#{arguments})
                assert_response :not_found
              end
              locale = "unsupported"
              get #{route_name}_path(#{arguments})
              assert_response :not_found
            end
          end
        RUBY
      end

      def system_test(route_name)
        arguments = @singleton ? "locale: locale" : 'locale: locale, permalink: "synthetic-path"'
        <<~RUBY
          require "test_helper"
          require "paradem_cms_site/testing/system_test_case"

          class Cms#{name}SystemTest < ParademCmsSite::Testing::SystemTestCase
            test "required locale viewport pages render long synthetic content without skips" do
              payload = JSON.parse(file_fixture("cms_#{name.underscore}.json").read)
              payload["title"] += " long content" * 12
              each_cms_viewport do |locale|
                #{name}.where(locale: locale).delete_all
                #{name}.create!(cms_id: "cms-resource-system", locale: locale, render: true, permalink: "synthetic-path", cms_record: payload)
                visit #{route_name}_path(#{arguments})
                assert_selector "h1", text: payload.fetch("title")
                assert_selector "html[lang='\#{locale.tr('_', '-')}']"
                assert_cms_accessibility
                page.save_screenshot(Rails.root.join("tmp/screenshots/cms-#{name.underscore}-\#{locale}-\#{page.evaluate_script('innerWidth')}.png"))
              end
            end
          end
        RUBY
      end

      def component_test
        <<~RUBY
          require "test_helper"
          require "view_component/test_case"

          class Site#{name}ComponentTest < ViewComponent::TestCase
            test "synthetic content is escaped and missing optional fields do not crash" do
              payload = JSON.parse(file_fixture("cms_#{name.underscore}.json").read)
              record = #{name}.new(cms_record: payload.merge("title" => "<script>unsafe()</script>"))
              render_inline(Site::#{name}Component.new(record: record))
              assert_selector "h1", text: "<script>unsafe()</script>"
              assert_no_selector "script"
              record.cms_record = {"title" => "Missing optional content"}
              render_inline(Site::#{name}Component.new(record: record))
              assert_selector "h1", text: "Missing optional content"
              record.cms_record = {"title" => nil}
              render_inline(Site::#{name}Component.new(record: record))
              assert_selector "h1", text: #{name.underscore.humanize.inspect}
            end
          end
        RUBY
      end
    end
  end
end
