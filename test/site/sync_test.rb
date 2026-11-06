# frozen_string_literal: true

require_relative "test_helper"
require "active_record"
require "paradem_cms_site/sync"

class SyncTest < Minitest::Test
  class StringRecord < ActiveRecord::Base
    self.table_name = "string_records"
    self.inheritance_column = nil
    enum :locale, {en: "en", fr: "fr"}
  end

  class IntegerRecord < ActiveRecord::Base
    self.table_name = "integer_records"
    self.inheritance_column = nil
    enum :locale, {en: 0, fr: 1}
  end

  class DerivedRow < ActiveRecord::Base
    self.table_name = "derived_rows"
  end

  Response = Struct.new(:data, :errors)
  Errors = Struct.new(:all)

  class Client
    attr_reader :calls
    attr_accessor :before_query

    def initialize(responses)
      @responses = responses
      @calls = []
      @mutex = Mutex.new
    end

    def query(operation, variables:, context:)
      @mutex.synchronize { @calls << [operation, variables, context, Thread.current] }
      before_query&.call(operation)
      value = @responses.fetch([operation, variables.fetch(:skip, 0)])
      raise value if value.is_a?(Exception)
      value.is_a?(Response) ? value : Response.new(value, Errors.new([]))
    end
  end

  def setup
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    connection = ActiveRecord::Base.connection
    %w[string_records integer_records].each do |table|
      connection.create_table(table) do |t|
        t.string :type, null: false
        (table == "string_records") ? t.string(:locale, null: false) : t.integer(:locale, null: false)
        t.string :cms_id, null: false
        t.boolean :render, null: false
        t.string :permalink
        t.json :cms_record, null: false
      end
      connection.add_index(table, [:type, :locale, :cms_id], unique: true)
      connection.add_index(table, [:locale, :permalink], unique: true, where: "permalink IS NOT NULL")
    end
    connection.create_table(:derived_rows) { |t| t.string :value }
    [StringRecord, IntegerRecord, DerivedRow].each(&:reset_column_information)
  end

  def teardown
    ActiveRecord::Base.connection_pool.disconnect!
  end

  def query(name, single: false, page_size: 2)
    Class.new do
      define_singleton_method(:query_name) { name }
      define_singleton_method(:single_instance?) { single }
      define_singleton_method(:graphql_page_size) { page_size }
      define_singleton_method(:render?) { true }
      const_set(:META_DATA, "#{name}:count")
      const_set(:INDEX, "#{name}:index")
      const_set(:SINGLE, "#{name}:single")
    end
  end

  def with_sync(locales: %w[en fr], singleton: true, count: 2, responses: nil, **options)
    names = singleton ? %w[Page Global] : %w[Page]
    with_site(generated: false, queries: names) do |root, data|
      data["locales"] = locales
      data["locale_mapping"] = locales.each_with_index.to_h
      manifest = ParademCmsSite::Manifest.new(data, root: root)
      queries = [query("Page")]
      queries << query("Global", single: true) if singleton
      responses ||= {
        ["Page:count", 0] => {"metaData" => {"count" => count}},
        ["Page:index", 0] => locales.to_h { |locale| ["#{locale}Items", [{"id" => "one", "permalink" => "first", "coverImage" => {"altText" => "Synthetic"}}, {"id" => "two", "permalink" => "second"}]] },
        ["Global:single", 0] => locales.to_h { |locale| ["#{locale}Item", {"id" => "global", "title" => "Synthetic"}] }
      }
      client = Client.new(responses)
      sync = ParademCmsSite::Sync.new(manifest: manifest, queries: queries, client: client, record_class: IntegerRecord, coordinator: Mutex.new, **options)
      yield sync, client, responses, manifest, queries
    end
  end

  def seed_cache
    IntegerRecord.create!(type: "Page", locale: "en", cms_id: "last-good", render: true, permalink: "last-good", cms_record: {"id" => "last-good"})
    DerivedRow.create!(value: "last-good")
  end

  def assert_last_good
    assert_equal ["last-good"], IntegerRecord.pluck(:cms_id)
    assert_equal ["last-good"], DerivedRow.pluck(:value)
  end

  def test_four_consumer_contracts_preserve_locales_identity_and_permalink_projection
    contracts = [
      ["bic", %w[en], "string", {"en" => "en"}, StringRecord, "permalink"],
      ["bahai_canada", %w[en fr], "integer", {"en" => 0, "fr" => 1}, IntegerRecord, "permalink"],
      ["cbns", %w[en fr], "integer", {"en" => 0, "fr" => 1}, IntegerRecord, "permalink"],
      ["afnan_library", %w[en], "integer", {"en" => 0}, IntegerRecord, "slug"]
    ]
    contracts.each do |site, locales, storage, mapping, records, permalink_field|
      with_site(generated: false) do |root, data|
        records.delete_all
        data.merge!("site" => site, "locales" => locales, "locale_storage" => storage, "locale_mapping" => mapping,
          "permalink_fields" => {"Page" => permalink_field})
        manifest = ParademCmsSite::Manifest.new(data, root: root)
        client = Client.new({
          ["Page:count", 0] => {"metaData" => {"count" => 1}},
          ["Page:index", 0] => locales.to_h { |locale| ["#{locale}Items", [{"id" => "page", permalink_field => "#{locale}-page"}]] },
          ["Global:single", 0] => locales.to_h { |locale| ["#{locale}Item", {"id" => "global"}] }
        })
        callbacks = []
        result = ParademCmsSite::Sync.new(manifest: manifest, queries: [query("Page"), query("Global", single: true)], client: client,
          record_class: records, coordinator: Mutex.new, after_sync: ->(summary) { callbacks << summary }).call
        assert_equal site, result.site
        assert_equal locales.length * 2, result.record_count
        assert_equal [result], callbacks
        assert result.frozen?
        locales.each do |locale|
          page = records.find_by!(type: "Page", locale: locale)
          assert_equal "page", page.cms_id
          assert_equal "#{locale}-page", page.permalink
          assert_equal mapping.fetch(locale), page.locale_before_type_cast
        end
        assert client.calls.all? { |_, _, context, _| context == {include_drafts: false} }
      end
    end
  end

  def test_lazy_client_creation_is_coordinated_before_fetch_without_a_database_writer
    with_sync do |_sync, client, _responses, manifest, queries|
      locked = false
      coordinator = Object.new
      coordinator.define_singleton_method(:synchronize) do |&block|
        locked = true
        block.call
      ensure
        locked = false
      end
      built = false
      factory = lambda do
        assert locked
        refute IntegerRecord.connection.transaction_open?
        built = true
        client
      end
      service = ParademCmsSite::Sync.new(manifest: manifest, queries: queries, client: factory,
        record_class: IntegerRecord, coordinator: coordinator)
      refute built
      assert_equal 6, service.call.record_count
      assert built
    end
  end

  def test_only_explicit_optional_singletons_may_be_null
    with_sync do |_sync, client, responses, manifest, queries|
      responses[["Global:single", 0]] = {"enItem" => nil, "frItem" => {"id" => "global"}}
      optional = ParademCmsSite::Manifest.new(manifest.data.merge("optional_singletons" => ["Global"]), root: manifest.root)
      result = ParademCmsSite::Sync.new(manifest: optional, queries: queries, client: client,
        record_class: IntegerRecord, coordinator: Mutex.new).call
      assert_equal 5, result.record_count
      assert_equal ["fr"], IntegerRecord.where(type: "Global").map(&:locale)
      invalid = ParademCmsSite::Manifest.new(manifest.data.merge("optional_singletons" => ["Page"]), root: manifest.root)
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::Sync.new(manifest: invalid, queries: queries, client: client,
          record_class: IntegerRecord, coordinator: Mutex.new)
      end
    end
  end

  def test_fetch_precedes_transaction_local_indexes_share_it_and_external_work_follows_commit
    seed_cache
    thread = Thread.current
    events = []
    within_transaction = lambda do |result|
      assert_equal thread, Thread.current
      assert ActiveRecord::Base.connection.transaction_open?
      assert_equal 6, IntegerRecord.count
      DerivedRow.delete_all
      DerivedRow.create!(value: result.site)
      events << :local
    end
    after_sync = lambda do |result|
      assert_equal thread, Thread.current
      refute ActiveRecord::Base.connection.transaction_open?
      assert_equal [result.site], DerivedRow.pluck(:value)
      events << :external
    end
    with_sync(within_transaction: within_transaction, after_sync: after_sync) do |sync, client|
      client.before_query = ->(_) { events << :fetch if Thread.current == thread }
      result = sync.call
      assert_equal 6, result.record_count
      assert_equal [:local, :external], events.last(2)
      refute_includes IntegerRecord.pluck(:cms_id), "last-good"
      assert_equal "Synthetic", IntegerRecord.find_by!(cms_id: "one").cms_record.dig("cover_image", "alt_text")
    end
  end

  def test_nested_graphql_errors_preserve_cache_and_do_not_invoke_callbacks
    seed_cache
    called = false
    with_sync(after_sync: ->(_) { called = true }) do |sync, _, responses|
      responses[["Page:index", 0]] = Response.new({"enItems" => []}, Errors.new({"nestedField" => "synthetic failure"}))
      error = assert_raises(ParademCmsSite::Sync::FetchError) { sync.call }
      refute_includes error.message, "synthetic failure"
      assert_last_good
      refute called
    end
  end

  def test_later_page_network_failure_preserves_cache
    seed_cache
    with_sync(count: 3) do |sync, _, responses|
      responses[["Page:index", 2]] = IOError.new("synthetic network failure")
      assert_raises(IOError) { sync.call }
      assert_last_good
    end
  end

  def test_invalid_counts_never_replace_cache
    seed_cache
    [nil, -1, "2", 1.5].each do |count|
      with_sync(count: count) do |sync|
        assert_raises(ParademCmsSite::Sync::FetchError) { sync.call }
        assert_last_good
      end
    end
  end

  def test_missing_locale_short_pages_duplicate_ids_and_malformed_rows_preserve_cache
    seed_cache
    [
      {"enItems" => [{"id" => "one"}, {"id" => "two"}]},
      {"enItems" => [{"id" => "one"}], "frItems" => [{"id" => "one"}]},
      {"enItems" => [{"id" => "one"}, {"id" => "one"}], "frItems" => [{"id" => "one"}, {"id" => "two"}]},
      {"enItems" => [{"id" => " one"}, {"id" => "two"}], "frItems" => []},
      {"enItems" => [nil, {"id" => "two"}], "frItems" => []},
      {"enItems" => nil, "frItems" => []}
    ].each do |data|
      with_sync do |sync, _, responses|
        responses[["Page:index", 0]] = data
        assert_raises(ParademCmsSite::Sync::FetchError) { sync.call }
        assert_last_good
      end
    end
  end

  def test_missing_required_singleton_preserves_cache
    seed_cache
    with_sync do |sync, _, responses|
      responses[["Global:single", 0]] = {"enItem" => nil, "frItem" => {"id" => "global"}}
      assert_raises(ParademCmsSite::Sync::FetchError) { sync.call }
      assert_last_good
    end
  end

  def test_valid_empty_collection_replaces_stale_records
    seed_cache
    with_sync(singleton: false, count: 0) do |sync, client|
      result = sync.call
      assert_equal 0, result.record_count
      assert_equal 0, IntegerRecord.count
      assert_equal ["Page:count"], client.calls.map(&:first)
    end
  end

  def test_database_failure_rolls_back_content_and_does_not_run_after_sync
    seed_cache
    called = false
    with_sync(after_sync: ->(_) { called = true }) do |sync, _, responses|
      responses[["Page:index", 0]].each_value { |items| items.each { |item| item["permalink"] = "collision" } }
      assert_raises(ActiveRecord::RecordNotUnique) { sync.call }
      assert_last_good
      refute called
    end
  end

  def test_local_index_failure_rolls_back_content_and_index
    seed_cache
    called = false
    local = lambda do |_|
      DerivedRow.delete_all
      DerivedRow.create!(value: "candidate")
      raise "synthetic local index failure"
    end
    with_sync(within_transaction: local, after_sync: ->(_) { called = true }) do |sync|
      assert_raises(RuntimeError) { sync.call }
      assert_last_good
      refute called
    end
  end

  def test_explicit_active_record_rollback_is_not_reported_as_a_successful_sync
    seed_cache
    called = false
    local = lambda do |_|
      DerivedRow.delete_all
      raise ActiveRecord::Rollback
    end
    with_sync(within_transaction: local, after_sync: ->(_) { called = true }) do |sync|
      assert_raises(ParademCmsSite::Sync::TransactionError) { sync.call }
      assert_last_good
      refute called
    end
  end

  def test_after_sync_failure_reports_committed_content_without_rolling_it_back
    seed_cache
    original = RuntimeError.new("synthetic external indexing failure")
    with_sync(after_sync: ->(_) { raise original }) do |sync|
      error = assert_raises(ParademCmsSite::Sync::AfterSyncError) { sync.call }
      assert_same original, error.cause
      assert_equal 6, error.result.record_count
      assert_equal 6, IntegerRecord.count
      refute_includes IntegerRecord.pluck(:cms_id), "last-good"
      refute_includes error.message, original.message
    end
  end

  def test_outer_transaction_is_rejected_before_fetch_or_callbacks
    seed_cache
    with_sync do |sync, client|
      IntegerRecord.transaction do
        assert_raises(ParademCmsSite::ConfigurationError) { sync.call }
        assert_empty client.calls
      end
      assert_last_good
    end
  end

  def test_query_registry_and_pool_options_are_explicit
    with_sync do |_, client, _, manifest, queries|
      [[], queries + [query("Other")], queries + [queries.first]].each do |registry|
        assert_raises(ParademCmsSite::ConfigurationError) do
          ParademCmsSite::Sync.new(manifest: manifest, queries: registry, client: client, record_class: IntegerRecord)
        end
      end
      [0, -1, "6"].each do |concurrency|
        assert_raises(ParademCmsSite::ConfigurationError) do
          ParademCmsSite::Sync.new(manifest: manifest, queries: queries, client: client, record_class: IntegerRecord, concurrency: concurrency)
        end
      end
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::Sync.new(manifest: manifest, queries: [query("Page", page_size: 0), queries.last], client: client, record_class: IntegerRecord)
      end
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::Sync.new(manifest: manifest, queries: queries, client: client, record_class: IntegerRecord, after_sync: "not callable")
      end
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::Sync.new(manifest: manifest, queries: queries, client: client, record_class: IntegerRecord, coordinator: "not a coordinator")
      end
      assert_empty client.calls
    end
  end

  def test_http_pool_is_bounded_and_preserves_page_order
    with_sync(locales: %w[en], count: 6, singleton: false, concurrency: 2) do |sync, client, responses|
      [0, 2, 4].each do |offset|
        responses[["Page:index", offset]] = {"enItems" => 2.times.map { |i| {"id" => "page-#{offset + i}"} }}
      end
      active = 0
      maximum = 0
      mutex = Mutex.new
      client.before_query = lambda do |operation|
        next unless operation == "Page:index"
        mutex.synchronize {
          active += 1
          maximum = [maximum, active].max
        }
        sleep 0.01
        mutex.synchronize { active -= 1 }
      end
      sync.call
      assert_equal 2, maximum
      assert_equal %w[page-0 page-1 page-2 page-3 page-4 page-5], IntegerRecord.order(:id).pluck(:cms_id)
    end
  end
end
