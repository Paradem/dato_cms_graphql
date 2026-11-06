# frozen_string_literal: true

require_relative "../paradem_cms_site"

module ParademCmsSite
  # Explicit runtime entry point. Loading the gem never starts a refresh.
  class Sync
    Result = Data.define(:site, :record_count)

    class FetchError < StandardError; end
    class TransactionError < StandardError; end

    # The content transaction has already committed. Retry the host's external
    # work separately; do not describe this as a rolled-back content refresh.
    class AfterSyncError < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super("CMS content committed, but the host after_sync callback failed")
      end
    end

    def initialize(manifest:, queries:, client:, record_class:, concurrency: 6,
      within_transaction: nil, after_sync: nil, coordinator: nil, environment: nil)
      @manifest = manifest
      @record_class = record_class
      @coordinator = coordinator
      if coordinator && !coordinator.respond_to?(:synchronize)
        raise ConfigurationError, "Sync coordinator must respond to synchronize"
      end
      build_source = lambda do |resolved|
        if defined?(GraphQL::Client::HTTP) && resolved.is_a?(GraphQL::Client) && resolved.execute.is_a?(GraphQL::Client::HTTP)
          require_relative "published_client"
          resolved = PublishedClient.new(client: resolved, environment: environment)
        end
        PublishedSource.new(manifest: manifest, queries: queries, client: resolved, concurrency: concurrency)
      end
      # Legacy schema introspection, when explicitly enabled by the host, must
      # also happen inside refresh coordination and outside the cache writer.
      @source_factory = client.respond_to?(:call) ? -> { build_source.call(client.call) } : nil
      @source = build_source.call(client) unless @source_factory
      @within_transaction = within_transaction
      @after_sync = after_sync
      [within_transaction, after_sync].compact.each do |callback|
        raise ConfigurationError, "Sync callbacks must respond to call" unless callback.respond_to?(:call)
      end
    end

    def call
      # Otherwise HTTP could run inside a caller's SQLite write transaction,
      # and returning from our savepoint would not mean the cache had committed.
      @record_class.connection_pool.with_connection do |connection|
        if connection.transaction_open?
          raise ConfigurationError, "Run CMS sync outside an existing database transaction"
        end
      end

      (@coordinator || FileLock.for_record(@record_class)).synchronize { refresh }
    end

    private

    def refresh
      rows = (@source_factory ? @source_factory.call : @source).fetch
      result = Result.new(site: @manifest.site, record_count: rows.length)
      outcome = @record_class.transaction do
        @record_class.delete_all
        @record_class.insert_all!(rows) unless rows.empty?
        @within_transaction&.call(result)
        result
      end
      raise TransactionError, "CMS cache transaction was rolled back" unless outcome.equal?(result)

      begin
        @after_sync&.call(result)
      rescue => error
        raise AfterSyncError.new(result), cause: error
      end
      result
    end
  end
end

require_relative "sync/published_source"
require_relative "sync/file_lock"
