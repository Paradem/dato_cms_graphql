#!/usr/bin/env ruby
# frozen_string_literal: true

# Credential-free refresh scale probe. It measures the delivered fetch/validate/
# replace path with authored synthetic records, not provider or production data.
require "active_record"
require "etc"
require "fileutils"
require "json"
require "tmpdir"
require "paradem_cms_site/sync"

ROWS = Integer(ENV.fetch("ROWS", "2895"))
PAYLOAD_KB = Integer(ENV.fetch("PAYLOAD_KB", "30"))
LOCALES = ENV.fetch("LOCALES", "en").split(",")
PAGE_SIZE = Integer(ENV.fetch("PAGE_SIZE", "100"))
CONCURRENCY = Integer(ENV.fetch("CONCURRENCY", "6"))

abort "ROWS must be positive" unless ROWS.positive?
abort "PAYLOAD_KB must be positive" unless PAYLOAD_KB.positive?
abort "LOCALES must be nonempty and unique" unless LOCALES.any? && LOCALES.uniq == LOCALES
abort "PAGE_SIZE and CONCURRENCY must be positive" unless PAGE_SIZE.positive? && CONCURRENCY.positive?

Response = Struct.new(:data, :errors)
Errors = Struct.new(:all)

class SyntheticPage
  INDEX = :page_index
  META_DATA = :page_count
  def self.query_name = "Page"
  def self.single_instance? = false
  def self.graphql_page_size = PAGE_SIZE
  def self.render? = true
end

class SyntheticGlobal
  SINGLE = :global_single
  def self.query_name = "Global"
  def self.single_instance? = true
  def self.render? = true
end

class SyntheticClient
  def initialize(rows:, payload_kb:, locales:, page_size:)
    @rows = rows
    @filler = "x" * (payload_kb * 1024)
    @locales = locales
    @page_size = page_size
  end

  def query(operation, variables:, context:)
    raise "draft context leaked" unless context == {include_drafts: false}
    skip = variables.fetch(:skip, 0)
    Response.new(data_for(operation, skip), Errors.new([]))
  end

  private

  def data_for(operation, skip)
    case operation
    when SyntheticPage::META_DATA then {"metaData" => {"count" => @rows}}
    when SyntheticPage::INDEX
      @locales.to_h do |locale|
        items = (skip...[skip + @page_size, @rows].min).map { |index| page(index, locale) }
        ["#{locale}Items", items]
      end
    when SyntheticGlobal::SINGLE
      @locales.to_h do |locale|
        ["#{locale}Item", {"id" => "global-#{locale}", "title" => "Synthetic global", "permalink" => "global-#{locale}"}]
      end
    else
      raise "unknown operation #{operation}"
    end
  end

  def page(index, locale)
    id = "synthetic-#{locale}-#{index}"
    {
      "id" => id,
      "title" => "Synthetic #{locale} page #{index}",
      "permalink" => "synthetic-#{locale}-#{index}",
      "summary" => @filler[0, 200],
      "body" => @filler,
      "sections" => 3.times.map do |section|
        {"id" => "#{id}-s#{section}", "blocks" => [
          {"type" => "prose", "text" => @filler[0, 1_000]},
          {"type" => "asset", "url" => "https://example.invalid/#{id}-#{section}.jpg"}
        ]}
      end,
      "coverImage" => {"url" => "https://example.invalid/#{id}.jpg", "altText" => "Synthetic image"},
      "categories" => [{"id" => "synthetic-category", "slug" => "synthetic"}]
    }
  end
end

class RssSampler
  def initialize(interval: 0.05)
    @peak = current
    @stop = false
    @thread = Thread.new do
      until @stop
        @peak = [@peak, current].max
        sleep interval
      end
    end
  end

  def stop
    @stop = true
    @thread.join
    [@peak, current].max
  end

  private

  def current
    if File.readable?("/proc/self/status")
      File.read("/proc/self/status")[/^VmRSS:\s+(\d+)/, 1].to_i
    else
      `ps -o rss= -p #{Process.pid}`.to_i
    end
  end
end

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

Dir.mktmpdir("cms-refresh-benchmark-") do |root|
  FileUtils.mkdir_p(File.join(root, "app/queries"))
  FileUtils.mkdir_p(File.join(root, "app/models"))
  mapping = LOCALES.each_with_index.to_h { |locale, index| [locale, index] }
  manifest_data = {
    "version" => 1, "site" => "synthetic_scale", "locales" => LOCALES,
    "locale_storage" => "integer", "locale_mapping" => mapping,
    "queries" => %w[Page Global], "generated_queries" => false,
    "query_path" => "app/queries", "model_path" => "app/models"
  }
  manifest = ParademCmsSite::Manifest.new(manifest_data, root: root)
  database = File.join(root, "benchmark.sqlite3")
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database)
  connection = ActiveRecord::Base.connection
  connection.create_table(:records) do |table|
    table.string :type, null: false
    table.integer :locale, null: false
    table.string :cms_id, null: false
    table.boolean :render, null: false
    table.string :permalink
    table.json :cms_record, null: false
  end
  connection.add_index :records, [:type, :locale, :cms_id], unique: true
  record_class = Class.new(ActiveRecord::Base) do
    self.table_name = "records"
    self.inheritance_column = nil
  end
  state = {}
  probe = Module.new do
    define_method(:fetch) do |*args, **kwargs, &block|
      state[:fetch_started] = now
      result = super(*args, **kwargs, &block)
      state[:fetch_finished] = now
      result
    end
  end
  ParademCmsSite::Sync::PublishedSource.prepend(probe)

  client = SyntheticClient.new(rows: ROWS, payload_kb: PAYLOAD_KB, locales: LOCALES, page_size: PAGE_SIZE)
  sync = ParademCmsSite::Sync.new(
    manifest: manifest, queries: [SyntheticPage, SyntheticGlobal], client: client,
    record_class: record_class, concurrency: CONCURRENCY, coordinator: Mutex.new,
    within_transaction: ->(_result) { state[:replace_finished] = now },
    after_sync: ->(_result) { state[:commit_finished] = now }
  )

  GC.start
  sampler = RssSampler.new
  started = now
  result = sync.call
  total = now - started
  peak_kb = sampler.stop

  raise "wrong row count" unless record_class.count == ROWS * LOCALES.length + LOCALES.length
  raise "wrong result" unless result.record_count == record_class.count

  puts JSON.pretty_generate(
    dataset: {
      collection_rows_per_locale: ROWS, locales: LOCALES, synthetic_records: result.record_count,
      payload_kb_target: PAYLOAD_KB, page_size: PAGE_SIZE, concurrency: CONCURRENCY,
      database_bytes: File.size(database)
    },
    timings_ms: {
      fetch_validate_materialize: (state.fetch(:fetch_finished) - state.fetch(:fetch_started)) * 1000,
      delete_insert: (state.fetch(:replace_finished) - state.fetch(:fetch_finished)) * 1000,
      commit_callbacks: (state.fetch(:commit_finished) - state.fetch(:replace_finished)) * 1000,
      total: total * 1000
    },
    peak_rss_mb: peak_kb / 1024.0,
    platform: {
      ruby: RUBY_VERSION, activerecord: ActiveRecord::VERSION::STRING,
      sqlite: connection.select_value("select sqlite_version()"),
      host_os: RbConfig::CONFIG.fetch("host_os"), host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
      processors: Etc.nprocessors, process_id: Process.pid
    },
    limits: "Synthetic in-process client; no provider latency, network, disk staging, host index or production data."
  )
ensure
  ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
end
