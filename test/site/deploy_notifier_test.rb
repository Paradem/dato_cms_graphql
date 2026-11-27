# frozen_string_literal: true

require_relative "test_helper"
require "logger"
require "stringio"
require "timeout"

class DeployNotifierTest < Minitest::Test
  ENDPOINT = "https://webhooks.example.test/synthetic-deploy-token/deploy-results"

  class FakeHTTP
    attr_reader :host, :port, :requests, :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_writer :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_accessor :response, :error

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @requests = []
    end

    def assign(host, port)
      @host = host
      @port = port
      self
    end

    def start
      yield self
    end

    def request(request)
      @requests << request
      raise error if error

      response
    end
  end

  def with_http(fake)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |host, port| fake.assign(host, port) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def notify(fake, url: ENDPOINT, timeout: ParademCmsSite::DeployNotifier::DEFAULT_TIMEOUT, status: "success")
    @logs = StringIO.new
    with_http(fake) do
      ParademCmsSite::DeployNotifier.new(url: url, timeout: timeout, logger: Logger.new(@logs)).call(status: status)
    end
  end

  def test_posts_json_status_to_the_configured_https_endpoint_with_bounded_timeouts
    fake = FakeHTTP.new(response: Net::HTTPOK.new("1.1", "200", "OK"))

    assert notify(fake)
    assert_equal "webhooks.example.test", fake.host
    assert_equal 443, fake.port
    assert fake.use_ssl
    assert_equal 5, fake.open_timeout
    assert_equal 5, fake.read_timeout
    assert_equal 5, fake.write_timeout
    request = fake.requests.fetch(0)
    assert_equal "/synthetic-deploy-token/deploy-results", request.path
    assert_equal "application/json", request["Content-Type"]
    assert_equal({"status" => "success"}, JSON.parse(request.body))
    assert_empty @logs.string
  end

  def test_callable_url_and_custom_timeout_are_resolved_at_call_time
    fake = FakeHTTP.new(response: Net::HTTPOK.new("1.1", "204", "No Content"))
    endpoint = ENDPOINT

    assert notify(fake, url: -> { endpoint }, timeout: 0.5, status: "error")
    assert_equal 0.5, fake.open_timeout
    assert_equal 0.5, fake.read_timeout
    assert_equal 0.5, fake.write_timeout
    assert_equal({"status" => "error"}, JSON.parse(fake.requests.fetch(0).body))
  end

  def test_class_method_reads_the_environment_by_default
    previous = ENV["DATO_DEPLOY_RESULT_URL"]
    ENV["DATO_DEPLOY_RESULT_URL"] = ENDPOINT
    fake = FakeHTTP.new(response: Net::HTTPOK.new("1.1", "200", "OK"))
    logs = StringIO.new

    result = with_http(fake) do
      ParademCmsSite::DeployNotifier.call(status: "success", logger: Logger.new(logs))
    end

    assert result
    assert_equal "/synthetic-deploy-token/deploy-results", fake.requests.fetch(0).path
    assert_empty logs.string
  ensure
    ENV["DATO_DEPLOY_RESULT_URL"] = previous
  end

  def test_non_2xx_response_is_logged_without_the_endpoint_or_token
    fake = FakeHTTP.new(response: Net::HTTPResponse::CODE_TO_OBJ.fetch("500").new("1.1", "500", "Internal Server Error"))

    refute notify(fake)
    assert_includes @logs.string, "HTTP 500"
    refute_includes @logs.string, ENDPOINT
    refute_includes @logs.string, "synthetic-deploy-token"
  end

  def test_transport_failure_is_logged_without_the_exception_message_endpoint_or_token
    fake = FakeHTTP.new(error: Timeout::Error.new("synthetic timeout at #{ENDPOINT}"))

    refute notify(fake)
    assert_includes @logs.string, "Timeout::Error"
    refute_includes @logs.string, "synthetic timeout"
    refute_includes @logs.string, ENDPOINT
    refute_includes @logs.string, "synthetic-deploy-token"
  end

  def test_missing_or_invalid_endpoint_is_a_logged_no_op
    [nil, "", "  ", "http://webhooks.example.test/synthetic-deploy-token/deploy-results",
      "not a URL #{ENDPOINT}"].each do |url|
      fake = FakeHTTP.new(response: Net::HTTPOK.new("1.1", "200", "OK"))

      refute notify(fake, url: url)
      assert_empty fake.requests
      assert_includes @logs.string, "DatoCMS deploy result notification"
      refute_includes @logs.string, ENDPOINT
      refute_includes @logs.string, "synthetic-deploy-token"
    end
  end

  def test_invalid_timeouts_are_rejected
    [0, -1, Float::INFINITY, Float::NAN, "5"].each do |timeout|
      assert_raises(ParademCmsSite::ConfigurationError) do
        ParademCmsSite::DeployNotifier.new(url: ENDPOINT, timeout: timeout)
      end
    end
  end
end
