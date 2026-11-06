# frozen_string_literal: true

require "paradem_cms_site/rails"

namespace :cms do
  desc "Refresh the published CMS cache and run configured site callbacks"
  task sync: :environment do
    ParademCmsSite.refresh("source" => "cli")
  end

  namespace :sync do
    desc "Export schemas, regenerate owned queries and refresh the published cache"
    task all: :environment do
      require "paradem_cms_site/rails/full_sync"
      installation = ParademCmsSite.configuration.installation
      abort "Configure the Rails CMS installation first" unless installation
      ParademCmsSite::FullSync.new(installation).call
    end
  end

  namespace :schema do
    desc "Write the published CDA schema snapshot without generating queries or refreshing content"
    task snapshot: :environment do
      require "paradem_cms_site/rails/schema_snapshot"
      installation = ParademCmsSite.configuration.installation
      abort "Configure the Rails CMS installation first" unless installation
      ParademCmsSite::SchemaSnapshot.call(installation.manifest)
      installation.reset_client!
    end
  end

  desc "Refresh at server boot with the configured last-good-cache policy"
  task boot: :environment do
    installation = ParademCmsSite.configuration.installation
    abort "Configure the Rails CMS installation first" unless installation
    installation.boot!
  end

  desc "Check the installed CMS integration without fetching or changing content"
  task doctor: :environment do
    installation = ParademCmsSite.configuration.installation
    abort "Run the Rails CMS install generator first" unless installation
    problems = ParademCmsSite::RailsDoctor.new(installation).problems
    abort problems.join("\n") unless problems.empty?
    puts "OK #{installation.manifest.site}: installed CMS configuration, queries, cache and webhook wiring"
    puts "Offline checks only; live credentials, queue execution and cache freshness are not verified."
  end
end

# Preserve the existing developer task name only for installed applications;
# legacy consumers retain their own task until they deliberately adopt setup.
path = ::Rails.application.root.join("config/cms_site.yml")
if path.file? && ParademCmsSite::Manifest.load(root: ::Rails.application.root).data["rails"]
  # Existing scripts/operators and cached command names resolve to the same
  # implementation, not a second refresh path with different safety rules.
  task cache_dato: "cms:sync"
  namespace :dato_cms do
    task cache: "cms:sync"
  end
  namespace :sync do
    task all: "cms:sync:all"
  end

  namespace :queries do
    desc "Generate one explicitly owned query from a local CMA schema export"
    task :generate, [:type_name] => :environment do |_task, args|
      require "paradem_cms_site/query_generation"
      manifest = ParademCmsSite::Manifest.load(root: ::Rails.application.root)
      name = args[:type_name]
      abort "Usage: bin/rails queries:generate[Model]" unless name
      result = ParademCmsSite::QueryGeneration::QueryGenerator.from_manifest(manifest).generate(
        name, force: ENV["FORCE"] == "1", dry_run: ENV["DRY_RUN"] == "1"
      )
      puts((ENV["DRY_RUN"] == "1") ? result.fetch(:contents) : result.fetch(:path))
    rescue ArgumentError, KeyError, IOError => error
      abort error.message
    end
  end
end
