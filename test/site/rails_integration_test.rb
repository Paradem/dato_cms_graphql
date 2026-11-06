# frozen_string_literal: true

require_relative "test_helper"
require "active_record"
require "rack/test"
require "active_job/test_helper"
require "paradem_cms_site/rails"

class RailsIntegrationTest < Minitest::Test
  include Rack::Test::Methods
  include ActiveJob::TestHelper

  SECRET = "synthetic-webhook-only"
  ROUTES = ActionDispatch::Routing::RouteSet.new
  ROUTES.draw { post "/webhooks/dato", to: "paradem_cms_site/webhooks#create" }

  class Record < ActiveRecord::Base
    self.table_name = "webhook_records"
    self.inheritance_column = nil
  end

  class PageQuery
    META_DATA = "count"
    INDEX = "pages"
    def self.query_name = "Page"
    def self.single_instance? = false
    def self.graphql_page_size = 100
    def self.render? = true
  end

  Response = Struct.new(:data, :errors)
  Errors = Struct.new(:all)

  class Client
    attr_reader :calls
    attr_accessor :failure

    def initialize
      @calls = []
    end

    def query(operation, variables:, context:)
      calls << [operation, variables, context]
      raise failure if failure
      data = (operation == "count") ? {"metaData" => {"count" => 1}} : {"enItems" => [{"id" => "published", "permalink" => "published"}]}
      Response.new(data, Errors.new([]))
    end
  end

  def app = ROUTES

  def setup
    super
    @previous_config = ParademCmsSite.configuration
    ParademCmsSite.instance_variable_set(:@configuration, ParademCmsSite::Configuration.new)
    @previous_logger = ActiveJob::Base.logger
    @logs = StringIO.new
    ActiveJob::Base.logger = Logger.new(@logs)
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.create_table(:webhook_records) do |t|
      t.string :type
      t.string :locale
      t.string :cms_id
      t.boolean :render
      t.string :permalink
      t.json :cms_record
    end
    Record.reset_column_information
    Record.create!(type: "Page", locale: "en", cms_id: "last-good", render: true, cms_record: {})
    @client = Client.new
    @callbacks = []
    @refreshes = 0
    @failure = nil
    @coordinator = Mutex.new
    @root = Dir.mktmpdir("cms-rails-test-")
    data = {"version" => 1, "site" => "fixture", "locales" => ["en"], "locale_storage" => "string", "locale_mapping" => {"en" => "en"},
            "queries" => ["Page"], "generated_queries" => false, "query_path" => "queries", "model_path" => "models"}
    @manifest = ParademCmsSite::Manifest.new(data, root: @root)
    ParademCmsSite.configure do |config|
      config.webhook_authentication = ParademCmsSite::WebhookAuthentication.shared_header(secret: -> { SECRET })
      config.sync = lambda do |context|
        @refreshes += 1
        ParademCmsSite::Sync.new(manifest: @manifest, queries: [PageQuery], client: @client, record_class: Record,
          coordinator: @coordinator, after_sync: lambda { |result|
            raise @failure if @failure
            @callbacks << [result, context]
          }).call
      end
    end
  end

  def teardown
    ParademCmsSite.instance_variable_set(:@configuration, @previous_config)
    ActiveJob::Base.logger = @previous_logger
    ActiveRecord::Base.connection_pool.disconnect!
    FileUtils.remove_entry(@root)
    super
  end

  def shared_request(secret = SECRET, body = "")
    post "/webhooks/dato", body, "HTTP_WEBHOOK_AUTH" => secret, "CONTENT_TYPE" => "application/json"
  end

  def test_authenticated_request_enqueues_without_fetching_or_persisting
    assert_enqueued_with(job: ParademCmsSite::RefreshJob, args: [{}]) { shared_request }
    assert_equal 200, last_response.status
    assert_equal "OK", last_response.body
    assert_empty @client.calls
    assert_equal ["last-good"], Record.pluck(:cms_id)
    assert_empty performed_jobs
    assert_empty @callbacks
    refute_includes @logs.string, SECRET
  end

  def test_queued_job_and_direct_cli_boot_entry_point_use_the_same_configured_sync
    perform_enqueued_jobs { shared_request }
    assert_equal ["published"], Record.pluck(:cms_id)
    assert_equal 1, @refreshes
    assert_equal "fixture", @callbacks.first.first.site
    assert_equal({}, @callbacks.first.last)
    ParademCmsSite.refresh("source" => "cli")
    assert_equal 2, @refreshes
    assert_equal({"source" => "cli"}, @callbacks.last.last)
    assert @client.calls.all? { |_, _, context| context == {include_drafts: false} }
  end

  def test_missing_blank_and_incorrect_authentication_never_enqueue_or_build_context
    mapped = false
    ParademCmsSite.configuration.webhook_context = ->(_) {
      mapped = true
      {}
    }
    [nil, "", " ", "\t\n", "incorrect", "#{SECRET}x"].each do |supplied|
      assert_no_enqueued_jobs { shared_request(supplied) }
      assert_equal 401, last_response.status
      refute mapped
    end
    [nil, "", " ", "\t\n", "\u00a0"].each do |secret|
      ParademCmsSite.configuration.webhook_authentication = ParademCmsSite::WebhookAuthentication.shared_header(secret: -> { secret })
      assert_no_enqueued_jobs { shared_request(secret) }
      assert_equal 401, last_response.status
    end
    ParademCmsSite.configuration.webhook_authentication = nil
    assert_no_enqueued_jobs { shared_request }
    assert_equal 401, last_response.status
  end

  def test_hmac_uses_exact_raw_body_and_preserves_host_owned_context
    body = "{\"event_type\":\"item.unpublish\", \"id\":\"synthetic\"}\n"
    ParademCmsSite.configuration.webhook_authentication = ParademCmsSite::WebhookAuthentication.hmac_sha256(secret: -> { SECRET })
    ParademCmsSite.configuration.webhook_context = lambda do |request|
      assert_equal body, request.raw_post
      {"webhook_log_id" => 17}
    end
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)}"
    assert_enqueued_with(job: ParademCmsSite::RefreshJob, args: [{"webhook_log_id" => 17}]) do
      post "/webhooks/dato", body, "HTTP_X_DATO_SIGNATURE" => signature, "CONTENT_TYPE" => "application/json"
    end
    assert_equal 200, last_response.status
    perform_enqueued_jobs
    assert_equal({"webhook_log_id" => 17}, @callbacks.last.last)
    refute_includes @logs.string, body
    refute_includes @logs.string, signature
    refute_includes @logs.string, SECRET
  end

  def test_hmac_mismatch_missing_signature_and_tampered_payload_are_rejected
    ParademCmsSite.configuration.webhook_authentication = ParademCmsSite::WebhookAuthentication.hmac_sha256(secret: SECRET)
    body = "{}"
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)}"
    [nil, "", "sha256=invalid", signature.upcase].each do |supplied|
      assert_no_enqueued_jobs { post "/webhooks/dato", body, "HTTP_X_DATO_SIGNATURE" => supplied }
      assert_equal 401, last_response.status
    end
    assert_no_enqueued_jobs { post "/webhooks/dato", "{ }", "HTTP_X_DATO_SIGNATURE" => signature }
    assert_equal 401, last_response.status
  end

  def test_host_can_suppress_an_already_completed_event_after_authentication
    ParademCmsSite.configuration.webhook_context = ->(_) {}
    assert_no_enqueued_jobs { shared_request }
    assert_equal 200, last_response.status
    assert_equal "Already processed", last_response.body
  end

  def test_default_is_at_least_once_not_payload_hash_suppression
    assert_enqueued_jobs(2) { 2.times { shared_request(SECRET, "{}") } }
  end

  def test_enqueue_failure_does_not_acknowledge_success
    abort_enqueue = -> { throw :abort }
    ParademCmsSite::RefreshJob.set_callback(:enqueue, :before, abort_enqueue)
    begin
      assert_no_enqueued_jobs { shared_request }
      assert_equal 503, last_response.status
      assert_empty @client.calls
    ensure
      ParademCmsSite::RefreshJob.skip_callback(:enqueue, :before, abort_enqueue)
    end
  end

  def test_missing_sync_configuration_and_invalid_context_cannot_enqueue
    configured = ParademCmsSite.configuration.sync
    ParademCmsSite.configuration.sync = nil
    assert_raises(ParademCmsSite::ConfigurationError) { shared_request }
    assert_empty enqueued_jobs
    ParademCmsSite.configuration.sync = configured
    ParademCmsSite.configuration.webhook_context = ->(_) { "not a job context" }
    assert_raises(ParademCmsSite::ConfigurationError) { shared_request }
    assert_empty enqueued_jobs
  end

  def test_host_context_rejection_returns_bad_request_after_authentication_without_enqueueing
    ParademCmsSite.configuration.webhook_context = ->(_) { raise ParademCmsSite::WebhookRejected }
    assert_no_enqueued_jobs { shared_request }
    assert_equal 400, last_response.status
    assert_equal "Bad Request", last_response.body
    assert_empty @client.calls
  end

  def test_error_hooks_receive_context_without_replacing_the_original_failure
    original = IOError.new("synthetic fetch failure")
    @client.failure = original
    calls = []
    ParademCmsSite.configuration.on_error = ->(error, context) { calls << [error, context] }
    assert_same original, assert_raises(IOError) { ParademCmsSite.refresh("source" => "webhook") }
    assert_equal [[original, {"source" => "webhook"}]], calls
    assert_equal ["last-good"], Record.pluck(:cms_id)
    ParademCmsSite.configuration.on_error = ->(*) { raise "synthetic notification failure" }
    assert_same original, assert_raises(IOError) { ParademCmsSite.refresh("source" => "webhook") }
  end

  def test_fetch_failure_remains_a_failed_job_and_preserves_cache
    @client.failure = IOError.new("synthetic fetch failure")
    assert_raises(IOError) { ParademCmsSite::RefreshJob.perform_now({}) }
    assert_equal ["last-good"], Record.pluck(:cms_id)
    assert_empty @callbacks
    assert_empty enqueued_jobs
  end

  def test_busy_refresh_is_scheduled_for_retry_without_fetching
    @coordinator = Object.new
    def @coordinator.synchronize = raise(ParademCmsSite::Sync::LockTimeout)
    ParademCmsSite::RefreshJob.perform_now("source" => "webhook")
    assert_enqueued_with(job: ParademCmsSite::RefreshJob, args: [{"source" => "webhook"}])
    assert_empty @client.calls
    assert_equal ["last-good"], Record.pluck(:cms_id)
  end

  def test_external_callback_failure_is_reported_and_discarded_without_retrying_content
    @failure = RuntimeError.new("synthetic external failure")
    events = []
    reports = []
    reporter = Object.new
    reporter.define_singleton_method(:report) { |error, **options| reports << [error, options] }
    ActiveSupport.error_reporter.subscribe(reporter)
    subscriber = ActiveSupport::Notifications.subscribe("discard.active_job") { |*args| events << args.last }
    begin
      ParademCmsSite::RefreshJob.perform_now({})
      assert_equal ["published"], Record.pluck(:cms_id)
      assert_equal 1, @refreshes
      assert_empty enqueued_jobs
      assert_equal 1, events.length
      assert_instance_of ParademCmsSite::Sync::AfterSyncError, events.first.fetch(:error)
      assert_same events.first.fetch(:error), reports.first.first
      assert_equal "paradem_cms_site.after_sync", reports.first.last.fetch(:source)
    ensure
      ActiveSupport.error_reporter.unsubscribe(reporter)
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end
