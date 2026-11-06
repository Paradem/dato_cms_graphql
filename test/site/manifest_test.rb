# frozen_string_literal: true

require "test_helper"

class ManifestTest < Minitest::Test
  def test_characterizes_string_and_legacy_integer_hosts_without_rails
    with_site do |root, data|
      %w[bic bahai_canada cbns afnan_library].each do |site|
        profile = data.merge("site" => site)
        if site == "bic"
          profile.merge!("locales" => ["en"], "locale_storage" => "string", "locale_mapping" => {"en" => "en"})
        elsif site == "afnan_library"
          profile["locales"] = ["en"]
          profile["locale_mapping"] = {"en" => 0}
        end
        manifest = ParademCmsSite::Manifest.new(profile, root: root)
        assert_equal ["Page", "synthetic-id", "en"], manifest.identity_for("Page", locale: :en, payload: OpenStruct.new(id: "synthetic-id"))
        assert_equal "/sample", manifest.permalink_for("Page", payload: {permalink: "/sample"})
        assert manifest.data.frozen?
        assert manifest.queries.frozen?
      end
    end
  end

  def test_computed_slug_projection_is_explicit_and_does_not_use_local_ids
    with_site(generated: false) do |root, data|
      manifest = ParademCmsSite::Manifest.new(data.merge("permalink_fields" => {"Page" => "slug"}), root: root)
      assert_equal "source-slug", manifest.permalink_for("Page", payload: {id: "cms-id", slug: "source-slug", permalink: "stale"})
      assert_nil manifest.permalink_for("Global", payload: {id: "singleton"})
      assert_raises(ParademCmsSite::ConfigurationError) { manifest.identity_for("Page", locale: :de, payload: {id: "cms-id"}) }
      assert_raises(ParademCmsSite::ConfigurationError) { manifest.identity_for("SiblingSite", locale: :en, payload: {id: "cms-id"}) }
      assert_raises(ParademCmsSite::ConfigurationError) { manifest.identity_for("Page", locale: :en, payload: {id: " "}) }
      assert_raises(ParademCmsSite::ConfigurationError) { manifest.permalink_for("Page", payload: {slug: 1}) }
    end
  end

  def test_rejects_unknown_keys_bad_locale_mappings_and_unowned_projections
    with_site do |root, data|
      [
        data.merge("api_token" => "never-print-this"),
        data.merge("locale_mapping" => {"en" => 0}),
        data.merge("locale_mapping" => {"en" => 0, "fr" => 0}),
        data.merge("locale_mapping" => {"en" => "en", "fr" => "fr"}),
        data.merge("queries" => ["Page", "Page"]),
        data.merge("permalink_fields" => {"SiblingSite" => "slug"}),
        data.merge("optional_singletons" => ["SiblingSite"]),
        data.merge("optional_singletons" => ["Page", "Page"]),
        data.merge("optional_singletons" => nil)
      ].each do |invalid|
        error = assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Manifest.new(invalid, root: root) }
        refute_includes error.message, "never-print-this"
      end
    end
  end

  def test_paths_cannot_traverse_or_escape_through_symlinks
    with_site do |root, data|
      %w[../outside /tmp/outside].each do |path|
        assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Manifest.new(data.merge("query_path" => path), root: root) }
      end
      Dir.mktmpdir do |outside|
        File.symlink(outside, File.join(root, "escape"))
        assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Manifest.new(data.merge("query_path" => "escape/new"), root: root) }
      end
    end
  end

  def test_manifest_load_is_safe_and_immutable
    with_site do |root, _data|
      manifest = ParademCmsSite::Manifest.load(root: root)
      assert_equal "example", manifest.site
      assert_raises(FrozenError) { manifest.locale_mapping["en"] = 9 }
      File.write(File.join(root, "config/cms_site.yml"), "--- !ruby/object:Object {}\n")
      assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Manifest.load(root: root) }
    end
  end
end
