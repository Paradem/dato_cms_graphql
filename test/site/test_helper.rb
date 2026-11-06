# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "yaml"
require "paradem_cms_site"

module SiteFixtures
  def with_site(generated: true, queries: %w[Page Global])
    Dir.mktmpdir("cms-site-test-") do |root|
      %w[config/cms app/queries app/models].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
      data = {
        "version" => 1, "site" => "example", "locales" => %w[en fr],
        "locale_storage" => "integer", "locale_mapping" => {"en" => 0, "fr" => 1},
        "queries" => queries, "generated_queries" => generated,
        "query_path" => "app/queries", "model_path" => "app/models",
        "model_api_key_selection" => "blocks"
      }
      queries.each do |model|
        basename = model.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        # Doctor must never execute these files.
        File.write(File.join(root, "app/queries/#{basename}_query.rb"), "raise \"Do not load host Ruby\"\n")
        File.write(File.join(root, "app/models/#{basename}.rb"), "raise \"Do not load host Ruby\"\n")
      end
      if generated
        data["schema_export"] = "config/cms/models.ts"
        data["overrides_path"] = "app/queries/overrides.yml"
        schema = queries.map { |model| "export type #{model} = ItemTypeDefinition<Settings, 'synthetic', { title: { type: 'string'; }; }>;" }.join("\n")
        File.write(File.join(root, data["schema_export"]), schema)
        File.write(File.join(root, data["overrides_path"]), "{}\n")
      end
      File.write(File.join(root, "config/cms_site.yml"), YAML.dump(data))
      yield root, data
    end
  end
end

class Minitest::Test
  include SiteFixtures
end
