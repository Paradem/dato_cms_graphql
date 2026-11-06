# frozen_string_literal: true

require "test_helper"
require "ripper"
require "paradem_cms_site/query_generation"

class QueryGenerationTest < Minitest::Test
  Q = ParademCmsSite::QueryGeneration

  def schema_for(definitions)
    schema = Object.new
    schema.define_singleton_method(:definition_for) { |name| Q::SchemaLoader::Definition.new(fields: definitions.fetch(name)) }
    schema
  end

  def generator(root, overrides: {}, allowed_models: %w[Page Global])
    File.write(File.join(root, "app/queries/overrides.yml"), YAML.dump(overrides))
    Q::QueryGenerator.new(
      schema_path: File.join(root, "config/cms/models.ts"),
      output_dir: File.join(root, "app/queries"),
      overrides_path: File.join(root, "app/queries/overrides.yml"),
      model_dir: File.join(root, "app/models"), allowed_models: allowed_models
    )
  end

  def test_manifest_constructor_uses_site_paths_and_preserves_ownership
    with_site do |root, _data|
      manifest = ParademCmsSite::Manifest.load(root: root)
      before = Dir[File.join(root, "**/*")].select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
      tool = Q::QueryGenerator.from_manifest(manifest)
      result = tool.generate("Page", dry_run: true)
      assert_equal manifest.query_file_for("Page").to_s, result.fetch(:path)
      refute_includes result.fetch(:contents), ":_model_api_key"
      assert_raises(ArgumentError) { tool.generate("SiblingSite", dry_run: true) }
      assert_raises(ArgumentError) { Q::QueryGenerator.from_manifest(manifest, allowed_models: nil) }
      before.each { |path, bytes| assert_equal bytes, File.binread(path), path }
    end
  end

  def test_installed_manifest_uses_lazy_query_and_the_declared_cache_base
    with_site do |root, data|
      data["rails"] = {"cache_model" => "CmsRecord", "delivery_schema" => "config/cms/schema.graphql", "webhook" => "disabled"}
      manifest = ParademCmsSite::Manifest.new(data, root: root)
      output = File.join(root, "new-models")
      result = Q::QueryGenerator.from_manifest(manifest, model_dir: output).generate("Page", force: true)
      assert_includes result.fetch(:contents), "class PageQuery < ParademCmsSite::Query"
      assert_includes File.read(File.join(output, "page.rb")), "class Page < CmsRecord"
      assert_raises(ArgumentError) { Q::ClassFormatter.new("Page", [:id], base_class: "Injected::Class") }
    end
  end

  def test_manifest_constructor_retains_the_all_records_discriminator_policy
    with_site do |root, data|
      data["model_api_key_selection"] = "all"
      manifest = ParademCmsSite::Manifest.new(data, root: root)
      code = Q::QueryGenerator.from_manifest(manifest).generate("Page", dry_run: true).fetch(:contents)
      assert_includes code, ":_model_api_key"
    end
  end

  def test_manifest_constructor_honors_explicit_tooling_paths_without_relaxing_ownership
    with_site do |root, _data|
      manifest = ParademCmsSite::Manifest.load(root: root)
      schema = File.join(root, "alternate.ts")
      overrides = File.join(root, "alternate.yml")
      queries = File.join(root, "alternate/queries")
      models = File.join(root, "alternate/models")
      File.write(schema, "export type Page = ItemTypeDefinition<Settings, 'synthetic', { headline: { type: 'string'; }; }>;")
      File.write(overrides, YAML.dump("Page" => {fallback_locale: :none}))
      tool = Q::QueryGenerator.from_manifest(manifest, schema_path: schema, overrides_path: overrides, output_dir: queries, model_dir: models)
      result = tool.generate("Page")
      assert_equal File.join(queries, "page_query.rb"), result.fetch(:path)
      assert_includes result.fetch(:contents), ":headline"
      assert_includes result.fetch(:contents), "fallback_locale :none"
      assert File.file?(File.join(models, "page.rb"))
      assert_raises(ArgumentError) { tool.generate("SiblingSite") }
    end
  end

  def test_manifest_constructor_rejects_hand_authored_query_hosts
    with_site(generated: false) do |root, _data|
      error = assert_raises(ArgumentError) { Q::QueryGenerator.from_manifest(ParademCmsSite::Manifest.load(root: root)) }
      assert_match(/hand-authored/, error.message)
    end
  end

  def test_fallback_and_render_policy_precede_query_compilation
    with_site do |root, _data|
      result = generator(root, overrides: {"Page" => {single_instance: true, fallback_locale: :none, render: false}}).generate("Page", dry_run: true)
      code = result.fetch(:contents)
      assert_includes code, "fallback_locale :none"
      assert_includes code, "render false"
      assert_operator code.index("fallback_locale"), :<, code.index("graphql_fields")
      assert_operator code.index("render false"), :<, code.index("graphql_fields")
      refute_nil Ripper.sexp(code)
    end
  end

  def test_dry_run_writes_nothing_and_refuses_unowned_or_invalid_models
    with_site do |root, _data|
      tool = generator(root)
      before = Dir[File.join(root, "**/*")].select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
      first = tool.generate("Page", dry_run: true)
      assert_equal first, tool.generate("Page", dry_run: true)
      assert_raises(ArgumentError) { tool.generate("SiblingSite", dry_run: true) }
      assert_raises(ArgumentError) { tool.generate("../Page") }
      assert_raises(IOError) { tool.generate("Page") }
      before.each { |path, bytes| assert_equal bytes, File.binread(path), path }
      assert_equal before.keys.sort, Dir[File.join(root, "**/*")].select { |path| File.file?(path) }.sort
    end
  end

  def test_forced_query_generation_never_overwrites_existing_model_methods
    with_site do |root, _data|
      original_model = File.read(File.join(root, "app/models/page.rb"))
      result = generator(root).generate("Page", force: true)
      assert_equal result.fetch(:contents), File.read(result.fetch(:path))
      assert_equal original_model, File.read(File.join(root, "app/models/page.rb"))
    end
  end

  def test_both_historical_exclusion_spellings_are_supported_but_ambiguous_configuration_fails
    %i[exclude_fields excluded_fields].each do |key|
      overrides = Q::Overrides.new("Page" => {key => [":retired"]})
      selection = Q::SelectionBuilder.new(schema_for("Page" => {"title" => {"type" => "string"}, "retired" => {"type" => "string"}}), overrides).build("Page")
      assert_includes selection, :title
      refute_includes selection, :retired
    end
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {exclude_fields: [], excluded_fields: []}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {fallbak_locale: :none}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {fallback_locale: true}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {single_instance: "false"}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {link_fields: {category: [:id, 7]}}) }
  end

  def test_override_cycles_and_normalized_duplicates_fail_without_recursion
    cyclic = []
    cyclic << cyclic
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {graphql_fields: cyclic}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {"single_instance" => true, :single_instance => false}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {excluded_fields: [false]}) }
    assert_raises(ArgumentError) { Q::Overrides.new("Page" => {field_aliases: {title: false}}) }
    assert_raises(ArgumentError) { Q::ClassFormatter.new("Page", [:id], fallback_locale: "en, fr") }
    assert_raises(ArgumentError) { Q::ClassFormatter.new("Page", [:id], render: "false") }
  end

  def test_bic_aliases_and_additional_parent_fields_survive
    overrides = Q::Overrides.new("Page" => {field_aliases: {content: "section_content"}, additional_fields: [{parent: [:id]}]})
    fields = {"content" => {"type" => "structured_text"}, "parent_id" => {"type" => "string"}}
    selection = Q::SelectionBuilder.new(schema_for("Page" => fields), overrides).build("Page")
    assert_includes selection, {"section_content: content" => [:value]}
    assert_includes selection, {parent: [:id]}
    refute_includes selection, :parent_id
    code = Q::ClassFormatter.new("Page", selection).to_s
    assert_includes code, "\"section_content: content\": ["
    refute_nil Ripper.sexp(code)
    invalid = Q::Overrides.new("Page" => {field_aliases: {content: "bad: alias"}})
    assert_raises(ArgumentError) { Q::SelectionBuilder.new(schema_for("Page" => fields), invalid).build("Page") }
  end

  def test_canada_mapping_and_bic_fragment_links_normalize_to_the_same_selection
    fields = {"body" => {"type" => "structured_text", "blocks" => "ImageBlock", "inline_blocks" => ["ImageBlock"]}}
    definitions = {"Page" => fields, "ImageBlock" => {"image" => {"type" => "file"}}}
    fragment = {"... on PageRecord" => [:id, :title]}
    variants = [{"Page" => [:id, :title]}, [fragment]]
    selections = variants.map do |links|
      overrides = Q::Overrides.new("Page" => {structured_text_links: {body: links}})
      Q::SelectionBuilder.new(schema_for(definitions), overrides).build("Page")
    end
    assert_equal selections.first, selections.last
    body = selections.first.find { |item| item.is_a?(Hash) }.fetch(:body)
    assert_includes body, {links: [fragment]}
    assert body.any? { |item| item.is_a?(Hash) && item.key?(:blocks) }
    assert body.any? { |item| item.is_a?(Hash) && item.key?(:inline_blocks) }
  end

  def test_discriminator_policy_and_asset_copies_preserve_host_behavior
    schema = schema_for("Page" => {"image" => {"type" => "file"}}, "ImageBlock" => {})
    all = Q::SelectionBuilder.new(schema).build("Page")
    blocks = Q::SelectionBuilder.new(schema, model_api_key_selection: :blocks)
    refute_includes blocks.build("Page"), :_model_api_key
    assert_includes blocks.build("ImageBlock"), :_model_api_key
    assert_includes all, :_model_api_key
    all.find { |item| item.is_a?(Hash) }.fetch(:image).last.fetch(:focal_point) << :z
    assert_equal %i[x y], Q::SelectionBuilder::DEFAULT_ASSET_SELECTION.last.fetch(:focal_point)
  end

  def test_repeated_cyclic_branches_do_not_corrupt_the_ancestor_stack
    schema = schema_for("Page" => {"children" => {"type" => "rich_text", "blocks" => ["Page", "Page"]}})
    selection = Q::SelectionBuilder.new(schema).build("Page")
    children = selection.find { |item| item.is_a?(Hash) }.fetch(:children)
    assert_equal [{"... on PageRecord" => [:id]}, {"... on PageRecord" => [:id]}], children
  end

  def test_id_only_link_defaults_round_trip_as_reviewable_overrides
    with_site do |root, _data|
      schema = "export type Page = ItemTypeDefinition<Settings, 'synthetic', { category: { type: 'link'; }; }>;"
      File.write(File.join(root, "config/cms/models.ts"), schema)
      tool = generator(root)
      before = File.read(File.join(root, "app/queries/overrides.yml"))
      capture_io { tool.generate("Page", dry_run: true) }
      assert_equal before, File.read(File.join(root, "app/queries/overrides.yml"))
      capture_io { tool.generate("Page", force: true) }
      loaded = Q::Overrides.load(File.join(root, "app/queries/overrides.yml"))
      assert_equal({category: [:id]}, loaded.link_fields_for("Page"))
    end
  end
end
