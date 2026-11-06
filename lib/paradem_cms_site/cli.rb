# frozen_string_literal: true

require "optparse"
require_relative "../paradem_cms_site"

module ParademCmsSite
  class CLI
    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def run(arguments)
      args = arguments.dup
      return usage unless args.shift == "doctor"
      root = Dir.pwd
      parser = OptionParser.new { |options| options.on("--root PATH") { |value| root = value } }
      parser.parse!(args)
      return usage unless args.empty?
      manifest = Manifest.load(root: root)
      problems = Doctor.new(manifest).problems
      if problems.empty?
        @out.puts "OK #{manifest.site}: #{manifest.queries.length} owned queries, locales #{manifest.locales.join(", ")}, #{manifest.locale_storage} locale storage"
        @out.puts "Offline configuration only: runtime delivery, routes, credentials and cache freshness are not verified."
        0
      else
        problems.each { |problem| @err.puts problem }
        1
      end
    rescue ConfigurationError, OptionParser::ParseError => error
      @err.puts error.message
      1
    rescue SystemCallError
      @err.puts "Unable to read local CMS configuration"
      1
    end

    private

    def usage
      @err.puts "Usage: cms-site doctor [--root PATH]"
      1
    end
  end
end
