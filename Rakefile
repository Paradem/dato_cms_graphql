# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

# Keep legacy global-client fixtures out of the offline integration process.
# Both suites are required by the default task, not optional/skipped coverage.
namespace :test do
  Rake::TestTask.new(:core) do |task|
    task.libs << "test" << "lib"
    task.pattern = "test/*_test.rb"
    task.warning = false
  end

  Rake::TestTask.new(:site) do |task|
    task.libs << "test/site" << "lib"
    task.pattern = "test/site/**/*_test.rb"
    task.warning = false
  end
end

task test: ["test:core", "test:site"]
task default: :test
