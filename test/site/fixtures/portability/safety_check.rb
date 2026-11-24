require "active_job/test_helper"
require "json"

class PortabilityMarker < ApplicationRecord
end

def check(condition, message)
  raise message unless condition
end

def expect_failure(*types)
  begin
    yield
  rescue *types
    return
  end
  raise "Expected #{types.map(&:name).join(" or ")}"
end

def cache_rows
  CmsRecord.order(:id).map(&:attributes)
end

def fail_delivery(installation)
  installation.client.define_singleton_method(:query) { |*| raise IOError, "Synthetic portability delivery outage" }
end

manifest_path = Rails.root.join("config/cms_site.yml")
fixture_path = Rails.root.join("config/cms/fixture.json")
original_manifest = manifest_path.read
original_fixture = fixture_path.read
ActiveJob::Base.queue_adapter = :test
queue = ParademCmsSite::RefreshJob.queue_adapter
check(CmsRecord.count.zero?, "New site must start without cached content")
ParademCmsSite::RefreshJob.perform_later({"source" => "portability"})
check(queue.enqueued_jobs.length == 1 && CmsRecord.count.zero?, "Enqueue must not refresh inline")
ActiveJob::Base.execute(queue.enqueued_jobs.first)
queue.enqueued_jobs.clear
check(CmsRecord.count == 8, "Executed fixture refresh must populate eight rows")
check(Article.find_by!(locale: :fr).permalink == "fr-article", "Computed slug projection lost")
CmsRecord.connection.create_table(:portability_markers) { |table| table.string :value }
PortabilityMarker.create!(value: "last-good")
before = cache_rows
installation = ParademCmsSite.configuration.installation

begin
  fail_delivery(installation)
  expect_failure(IOError, ParademCmsSite::Sync::FetchError) { ParademCmsSite.refresh }
  check(cache_rows == before, "Failed fetch replaced the last-good cache")
  expect_failure(IOError, ParademCmsSite::Sync::FetchError) { installation.boot! }
  check(queue.enqueued_jobs.empty?, "Strict boot must not silently schedule a stale-cache fallback")

  manifest = YAML.safe_load(original_manifest)
  manifest.fetch("rails")["boot_fallback"] = true
  manifest_path.write(YAML.dump(manifest))
  installation = ParademCmsSite::Installation.new(root: Rails.root).configure!
  fail_delivery(installation)
  installation.boot!
  check(cache_rows == before, "Warm boot changed cached content")
  check(queue.enqueued_jobs.length == 1, "Warm fallback must enqueue one retry")
  check(ActiveJob::Arguments.deserialize(queue.enqueued_jobs.first.fetch(:args)) == [{"source" => "boot_retry"}], "Wrong retry context")
  queue.enqueued_jobs.clear
  CmsRecord.delete_all
  expect_failure(IOError, ParademCmsSite::Sync::FetchError) { installation.boot! }
  check(CmsRecord.count.zero? && queue.enqueued_jobs.empty?, "Cold boot must fail, not serve an empty fallback")
  CmsRecord.insert_all!(before)

  fixture = JSON.parse(original_fixture)
  fixture.fetch("Article").each_value { |rows| rows.first["title"] = "Candidate that must roll back" }
  fixture_path.write(JSON.pretty_generate(fixture) + "\n")
  installation.reset_client!
  ParademCmsSite.configuration.within_transaction = ->(*) do
    check(Article.first!.title == "Candidate that must roll back", "Failure probe never reached the candidate swap")
    PortabilityMarker.update_all(value: "candidate")
    raise ActiveRecord::StatementInvalid, "Synthetic derived-index failure"
  end
  expect_failure(ActiveRecord::StatementInvalid) { installation.boot! }
  check(cache_rows == before, "Persistence failure changed the last-good cache")
  check(PortabilityMarker.first!.value == "last-good", "Derived data escaped cache rollback")
  check(queue.enqueued_jobs.empty?, "Persistence error must not become a recoverable boot retry")
ensure
  manifest_path.write(original_manifest)
  fixture_path.write(original_fixture)
  ParademCmsSite.configuration.within_transaction = nil
  ParademCmsSite::Installation.new(root: Rails.root).configure!
end

check(cache_rows == before, "Safety probes did not restore the original cache")
check(ParademCmsSite::RailsDoctor.new(ParademCmsSite.configuration.installation).problems.empty?, "Doctor rejected the restored fixture installation")
puts "GENERATED_CACHE_SAFETY_PASS"
