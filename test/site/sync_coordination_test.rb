# frozen_string_literal: true

require_relative "test_helper"
require "active_record"
require "paradem_cms_site/sync"
require "rbconfig"
require "timeout"

class SyncCoordinationTest < Minitest::Test
  class Record < ActiveRecord::Base
    self.table_name = "records"
    self.inheritance_column = nil
  end

  class PageQuery
    META_DATA = "count"
    INDEX = "index"
    def self.query_name = "Page"
    def self.single_instance? = false
    def self.graphql_page_size = 100
    def self.render? = true
  end

  CHILD = <<~RUBY
    require "active_record"
    require "paradem_cms_site/sync"
    root, database, trace, identity, gate, stage = ARGV
    class CacheRecord < ActiveRecord::Base
      self.table_name = "records"
      self.inheritance_column = nil
    end
    CacheRecord.establish_connection(adapter: "sqlite3", database: database)
    class PageQuery
      META_DATA = "count"
      INDEX = "index"
      def self.query_name = "Page"
      def self.single_instance? = false
      def self.graphql_page_size = 100
      def self.render? = true
    end
    response = Struct.new(:data, :errors)
    errors = Struct.new(:all).new([])
    log = ->(event) { File.open(trace, "a") { |file| file.puts(identity + ":" + event) } }
    wait = lambda do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      until File.exist?(gate)
        raise "Synthetic gate timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.01
      end
    end
    client = Object.new
    client.define_singleton_method(:query) do |operation, variables:, context:|
      raise "Not published" unless context == {include_drafts: false}
      log.call(operation)
      wait.call if operation == "index" && stage == "fetch"
      data = (operation == "count") ? {"metaData" => {"count" => 1}} : {"enItems" => [{"id" => identity}]}
      response.new(data, errors)
    end
    callback = lambda do |_result|
      log.call("callback-start")
      wait.call if stage == "callback"
      log.call("callback-end")
    end
    log.call("ready")
    ParademCmsSite::Sync.new(manifest: ParademCmsSite::Manifest.load(root: root), queries: [PageQuery], client: client,
      record_class: CacheRecord, after_sync: callback).call
  RUBY

  def with_database
    with_site(generated: false, queries: ["Page"]) do |root, data|
      data.merge!("locales" => ["en"], "locale_storage" => "string", "locale_mapping" => {"en" => "en"})
      File.write(File.join(root, "config/cms_site.yml"), YAML.dump(data))
      database = File.join(root, "cache.sqlite3")
      Record.establish_connection(adapter: "sqlite3", database: database)
      Record.connection.create_table(:records) do |t|
        t.string :type
        t.string :locale
        t.string :cms_id
        t.boolean :render
        t.string :permalink
        t.json :cms_record
      end
      Record.connection.create_table(:unrelated) { |t| t.string :value }
      Record.reset_column_information
      Record.create!(type: "Page", locale: "en", cms_id: "last-good", render: true, cms_record: {})
      @children = []
      begin
        yield root, database, ParademCmsSite::Manifest.new(data, root: root)
      ensure
        @children.each do |pid|
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
        Record.connection_pool.disconnect!
      end
    end
  end

  def spawn_child(root, script, *arguments)
    environment = %w[PATH HOME GEM_HOME GEM_PATH BUNDLE_GEMFILE].to_h { |name| [name, ENV[name]] }
    stderr = File.join(root, "child-#{@children.length}.stderr")
    pid = Process.spawn(environment, RbConfig.ruby, "-rbundler/setup", "-Ilib", "-e", script, *arguments,
      unsetenv_others: true, out: File::NULL, err: stderr)
    @children << pid
    [pid, stderr]
  end

  def wait_for
    Timeout.timeout(10) { sleep 0.01 until yield }
  end

  def finish(child)
    pid, stderr = child
    status = Timeout.timeout(10) { Process.wait2(pid).last }
    @children.delete(pid)
    assert status.success?, File.read(stderr)
  end

  def test_two_processes_serialize_fetch_commit_and_callback_without_blocking_sqlite_writes
    %w[fetch callback].each do |stage|
      with_database do |root, database, _manifest|
        trace = File.join(root, "trace")
        gate = File.join(root, "continue")
        first = spawn_child(root, CHILD, root, database, trace, "first", gate, stage)
        marker = (stage == "fetch") ? "first:index" : "first:callback-start"
        wait_for { File.exist?(trace) && File.read(trace).include?(marker) }
        second = spawn_child(root, CHILD, root, database, trace, "second", gate, "none")
        wait_for { File.read(trace).include?("second:ready") }
        sleep 0.1
        refute_includes File.read(trace), "second:count", "Second refresh must not fetch while the first is active"
        Record.connection.execute("INSERT INTO unrelated (value) VALUES ('synthetic')")
        assert_equal 1, Record.connection.select_value("SELECT COUNT(*) FROM unrelated")
        File.write(gate, "continue")
        finish(first)
        finish(second)
        assert_equal %w[first:count first:index first:callback-start first:callback-end second:count second:index second:callback-start second:callback-end], File.readlines(trace, chomp: true).reject { |line| line.end_with?(":ready") }
        assert_equal ["second"], Record.pluck(:cms_id)
      end
    end
  end

  def test_lock_timeout_prevents_fetch_and_keeps_last_good_content
    with_database do |root, _database, manifest|
      path = File.join(root, "held.lock")
      coordinator = ParademCmsSite::Sync::FileLock.new(path: path, timeout: 0)
      client = Object.new
      def client.query(*) = raise("Unexpected fetch while lock is held")
      sync = ParademCmsSite::Sync.new(manifest: manifest, queries: [PageQuery], client: client, record_class: Record,
        coordinator: ParademCmsSite::Sync::FileLock.new(path: path, timeout: 0))
      coordinator.synchronize { assert_raises(ParademCmsSite::Sync::LockTimeout) { sync.call } }
      assert_equal ["last-good"], Record.pluck(:cms_id)
    end
  end

  def test_abnormal_process_exit_releases_lock_without_expiring_or_deleting_its_inode
    with_database do |root|
      path = File.join(root, "held.lock")
      ready = File.join(root, "ready")
      child = spawn_child(root, <<~RUBY, path, ready)
        require "paradem_cms_site/sync"
        ParademCmsSite::Sync::FileLock.new(path: ARGV[0]).synchronize do
          File.write(ARGV[1], "ready")
          sleep 60
        end
      RUBY
      wait_for { File.exist?(ready) }
      inode = File.stat(path).ino
      assert_raises(ParademCmsSite::Sync::LockTimeout) do
        ParademCmsSite::Sync::FileLock.new(path: path, timeout: 0).synchronize { flunk "Lock was stolen" }
      end
      Process.kill("KILL", child.first)
      Process.wait(child.first)
      @children.delete(child.first)
      assert_equal :acquired, ParademCmsSite::Sync::FileLock.new(path: path, timeout: 0).synchronize { :acquired }
      assert_equal inode, File.stat(path).ino
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_separate_threads_in_one_worker_also_contend_for_the_same_lock
    with_database do |root|
      path = File.join(root, "held.lock")
      acquired = Queue.new
      release = Queue.new
      thread = Thread.new do
        ParademCmsSite::Sync::FileLock.new(path: path).synchronize do
          acquired << true
          release.pop
        end
      end
      begin
        Timeout.timeout(5) { acquired.pop }
        assert_raises(ParademCmsSite::Sync::LockTimeout) do
          ParademCmsSite::Sync::FileLock.new(path: path, timeout: 0).synchronize { flunk "Thread lock was bypassed" }
        end
      ensure
        release << true
        thread.join
      end
    end
  end

  def test_exceptions_release_the_lock
    with_database do |root|
      lock = ParademCmsSite::Sync::FileLock.new(path: File.join(root, "held.lock"), timeout: 0)
      assert_raises(IOError) { lock.synchronize { raise IOError, "synthetic failure" } }
      assert_equal :released, lock.synchronize { :released }
    end
  end

  def test_invalid_timeouts_and_non_file_backends_require_explicit_configuration
    [-1, Float::INFINITY, Float::NAN, "30"].each do |timeout|
      assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Sync::FileLock.new(path: "unused", timeout: timeout) }
    end
    ["postgresql", "sqlite3"].each do |adapter|
      config = Struct.new(:adapter, :database).new(adapter, ":memory:")
      model = Object.new
      model.define_singleton_method(:connection_db_config) { config }
      assert_raises(ParademCmsSite::ConfigurationError) { ParademCmsSite::Sync::FileLock.for_record(model) }
    end
  end
end
