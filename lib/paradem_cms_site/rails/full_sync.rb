# frozen_string_literal: true

require "open3"
require "tempfile"
require "fileutils"
require_relative "schema_snapshot"
require_relative "../query_generation"

module ParademCmsSite
  # One explicit CLI lifecycle; published webhooks/boot never export or generate.
  # A failed preparation restores the last-good owned artifact set; the cache
  # refresh runs only after the whole set is prepared and reloaded.
  class FullSync
    class CommandError < StandardError; end

    def initialize(installation, command_runner: nil, output: $stdout)
      @installation = installation
      @manifest = installation.manifest
      @command_runner = command_runner || method(:run_command)
      @output = output
    end

    def call
      artifacts = ArtifactSet.capture(@manifest)
      begin
        prepare
      rescue
        artifacts.restore!
        raise
      end
      @output.puts "Refresh the published CMS cache"
      ParademCmsSite.refresh("source" => "cli")
    end

    private

    def prepare
      export_schema if @manifest.generated_queries?
      @output.puts "Snapshot the published GraphQL delivery schema"
      SchemaSnapshot.call(@manifest)
      if @manifest.generated_queries?
        @output.puts "Regenerate owned CMS queries"
        generator = QueryGeneration::QueryGenerator.from_manifest(@manifest)
        @manifest.queries.each { |name| generator.generate(name, force: true) }
        command!("Query formatting", "bundle", "exec", "standardrb", "--fix", @manifest.path_for(:query_path).to_s)
        @installation.reload_queries!
      else
        @installation.reset_client!
      end
    end

    def export_schema
      @output.puts "Export the CMS generation schema"
      destination = @manifest.path_for(:schema_export)
      Tempfile.create(["cms-generation-", ".json"], destination.dirname) do |file|
        arguments = ["npx", "datocms", "schema:generate", file.path, "--json"]
        selected = ENV["DATO_ENVIRONMENT"]
        arguments << "--environment=#{selected}" if selected && !selected.strip.empty?
        # The CLI's supported default token ENV, not argv, shell interpolation,
        # an auth helper, a token-bearing config file, or command logging.
        command!("Schema export", {"DATOCMS_API_TOKEN" => ENV.fetch("DATO_API_TOKEN")}, *arguments)
        schema = QueryGeneration::SchemaLoader.new(file.path)
        @manifest.queries.each { |name| schema.definition_for(name) }
        file.close
        File.rename(file.path, destination)
      end
    end

    def command!(stage, *arguments)
      raise CommandError, "#{stage} failed; the CMS cache was not refreshed" unless @command_runner.call(*arguments, chdir: @manifest.root.to_s)
    end

    def run_command(*arguments, chdir:)
      # Provider/subprocess output can contain configuration or data. Do not
      # echo it or include the invocation/environment in an exception.
      _stdout, _stderr, status = Open3.capture3(*arguments, chdir: chdir)
      status.success?
    end

    # Last-good bytes of the owned generation/delivery files. The export and
    # snapshot are individually renamed after validation, so restoring the
    # whole set is what keeps a failed run from activating mixed artifacts.
    class ArtifactSet
      def self.capture(manifest)
        paths = [manifest.path_for(:delivery_schema)]
        if manifest.generated_queries?
          paths.concat([manifest.path_for(:schema_export), manifest.path_for(:overrides_path)])
          manifest.queries.each do |name|
            paths.concat([manifest.query_file_for(name), manifest.model_file_for(name)])
          end
        end
        new(paths.compact.uniq)
      end

      def initialize(paths)
        @contents = paths.to_h { |path| [path, File.exist?(path) ? File.binread(path) : nil] }
      end

      def restore!
        @contents.each do |path, contents|
          if contents
            FileUtils.mkdir_p(File.dirname(path))
            File.binwrite(path, contents)
          else
            FileUtils.rm_f(path)
          end
        end
      end
    end
  end
end
