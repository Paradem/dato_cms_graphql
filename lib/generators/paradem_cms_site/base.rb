# frozen_string_literal: true

require "rails/generators"
require "paradem_cms_site"
require "digest"
require "json"

module ParademCmsSite
  module Generators
    class Base < ::Rails::Generators::Base
      hide!

      def self.exit_on_failure? = true

      Error = ::Rails::Generators::Error
      STATE_PATH = "config/cms/generators.json"

      private

      def checked_path(relative)
        root = Pathname(destination_root).realpath
        relative = Pathname(relative)
        if relative.absolute? || relative.each_filename.any? { |part| part == ".." } || relative.to_s.include?("\0")
          raise Error, "Generator paths must stay inside the Rails application"
        end
        path = root.join(relative)
        existing = path
        existing = existing.parent until existing.exist? || existing.symlink?
        unless existing.realpath == root || existing.realpath.to_s.start_with?("#{root}/")
          raise Error, "Generator paths must stay inside the Rails application"
        end
        path
      rescue Errno::ENOENT
        raise Error, "Dangling generator paths require review"
      end

      def state
        @state ||= begin
          path = checked_path(STATE_PATH)
          data = path.exist? ? JSON.parse(path.read) : {"version" => 1, "generators" => {}, "managed_files" => {}}
          unless data.is_a?(Hash) && data.keys.sort == %w[generators managed_files version] && data["version"] == 1 &&
              data["generators"].is_a?(Hash) && data["managed_files"].is_a?(Hash) &&
              data["managed_files"].values.all? { |digest| digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/) }
            raise Error, "Invalid generator ownership metadata; review #{STATE_PATH}"
          end
          data
        end
      rescue JSON::ParserError
        raise Error, "Invalid generator ownership metadata; review #{STATE_PATH}"
      end

      def managed_contents(relative)
        path = checked_path(relative)
        unless path.file? && state.fetch("managed_files")[relative] == Digest::SHA256.file(path).hexdigest
          raise Error, "Refusing to update customized or untracked #{relative}; review and merge it explicitly"
        end
        path.read
      end

      def write_scaffold(key, parameters, files, updates: {}, managed: [])
        raise Error, "Destroy is not supported; review host-owned files explicitly" unless behavior == :invoke
        entry = {"version" => ParademCmsSite::VERSION, "options" => parameters}
        if state.fetch("generators").key?(key) && state.fetch("generators").fetch(key) != entry
          raise Error, "Generator options/version changed for #{key}; review an upgrade rather than rerunning as an updater"
        end
        state.fetch("generators")[key] = entry
        managed.each { |path| state.fetch("managed_files")[path] = Digest::SHA256.hexdigest(files.fetch(path)) }
        metadata = checked_path(STATE_PATH)
        updates = updates.merge(STATE_PATH => metadata.file? ? metadata.read : nil)
        files = files.merge(STATE_PATH => JSON.pretty_generate(state) + "\n")
        files.each do |relative, contents|
          path = checked_path(relative)
          next unless path.exist?
          current = path.file? ? path.binread : nil
          unless current && [contents.b, updates[relative]&.b].include?(current)
            raise Error, "Refusing to overwrite #{relative}; review and merge the existing application file"
          end
        end
        # shortcut: writes are not an OS transaction, stage output first if interrupted-write recovery is required.
        files.each { |path, contents| create_file(path, contents, force: updates.key?(path)) }
      end

      def installed_manifest
        Manifest.load(root: destination_root)
      rescue ConfigurationError, Errno::ENOENT
        raise Error, "Install the CMS integration with a valid local manifest first"
      end

      def model_name!(name)
        unless name.match?(Manifest::MODEL_NAME) && name.underscore.camelize == name && !%w[Object Module Class Site ApplicationRecord ApplicationController].include?(name)
          raise Error, "Use a conventional model name (for example Article or PromoBlock)"
        end
      end

      def component_template(path)
        choices = ["#{path}.html.erb", "#{path}.erb"]
        existing = choices.select { |file| checked_path(file).exist? }
        raise Error, "Multiple component templates require review" if existing.length > 1
        existing.first || choices.first
      end

      def add_route(files, updates, declaration, key:, marker:, route_name:)
        path = "config/routes.rb"
        source = checked_path(path).read
        count = source.lines.count { |line| line.chomp == "  #{declaration}" }
        raise Error, "Duplicate generated routes require review" if count > 1
        if state.fetch("generators").key?(key)
          raise Error, "A generated route was customized or removed; review it explicitly" unless count == 1
          return
        end
        if count == 1 || source.include?(marker) || source.match?(/\bas:\s*:#{Regexp.escape(route_name)}\b/)
          raise Error, "An existing route conflicts with #{route_name}; review it explicitly"
        end
        anchor = /^Rails\.application\.routes\.draw do[ \t]*\n/
        raise Error, "Use a standard Rails routes file before generating routes" unless source.match?(anchor)
        updates[path] = source
        files[path] = source.sub(anchor) { |match| "#{match}  #{declaration}\n" }
      rescue Errno::ENOENT
        raise Error, "Run this generator inside a standard Rails application"
      end

      def require_view_component!
        collision = Object.const_defined?(:Site, false) && !Object.autoload?(:Site) && !Object.const_get(:Site, false).instance_of?(Module)
        if checked_path("app/models/site.rb").exist? || collision
          raise Error, "The Site presentation namespace collides with a host model/constant; integrate these starters manually"
        end
        unless Gem.loaded_specs.key?("view_component")
          raise Error, "Add view_component to the application's Gemfile before generating UI starters"
        end
      end

      def fixture_type(name, fields = %w[title permalink])
        "type #{name}Record { id: ID!, #{fields.map { |field| "#{field}: String" }.join(", ")}, _modelApiKey: String, _editingUrl: String, _seoMetaTags: [SeoTag!]! }"
      end

      def fixture_query_fields(name, singleton:)
        if singleton
          ["#{name.camelize(:lower)}(locale: SiteLocale, fallbackLocales: [SiteLocale!]): #{name}Record"]
        else
          ["all#{name.pluralize}(locale: SiteLocale, fallbackLocales: [SiteLocale!], first: IntType, skip: IntType): [#{name}Record!]!", "_all#{name.pluralize}Meta: RecordMeta!"]
        end
      end

      def test_helper_files
        return {} if checked_path("test/test_helper.rb").exist?
        {"test/test_helper.rb" => <<~RUBY}
          ENV["RAILS_ENV"] ||= "test"
          require_relative "../config/environment"
          require "rails/test_help"
        RUBY
      end

      def localized_controller(name, action, layout: nil)
        <<~RUBY
          # frozen_string_literal: true

          module Site
            class #{name}Controller < ApplicationController
          #{"    layout #{layout.inspect}\n" if layout}    around_action :with_cms_locale

              def show
          #{action}
              end

              private

              def with_cms_locale(&action)
                locale = params[:locale].to_s
                unless ParademCmsSite.configuration.installation.manifest.locales.include?(locale)
                  raise ActionController::RoutingError, "Not Found"
                end
                I18n.with_locale(locale, &action)
              end
            end
          end
        RUBY
      end
    end
  end
end
