# frozen_string_literal: true

require "digest"

module ParademCmsSite
  class Sync
    class LockTimeout < StandardError; end

    # All four consumers use file-backed SQLite. A separate flock serializes
    # HTTP + commit + callback without holding SQLite's writer while waiting.
    class FileLock
      def self.for_record(record_class)
        config = record_class.connection_db_config
        database = config.database.to_s
        unless config.adapter == "sqlite3" && !database.empty? && !database.include?(":memory:") && !database.start_with?("file:")
          raise ConfigurationError, "Supply a shared coordinator for non-file SQLite caches"
        end
        database = File.realpath(database)
        table = Digest::SHA256.hexdigest(record_class.table_name)[0, 12]
        new(path: "#{database}.#{table}.cms-sync.lock")
      end

      def initialize(path:, timeout: 30)
        unless timeout.is_a?(Numeric) && timeout.finite? && timeout >= 0
          raise ConfigurationError, "Sync lock timeout must be finite and nonnegative"
        end
        @path = path.to_s
        @timeout = timeout
      end

      def synchronize
        File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
          until file.flock(File::LOCK_EX | File::LOCK_NB)
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise LockTimeout, "Another CMS refresh is in progress" if remaining <= 0
            sleep [remaining, 0.05].min
          end
          begin
            yield
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      end
    end
  end
end
