# frozen_string_literal: true

module ParademCmsSite
  class RefreshJob < ActiveJob::Base
    queue_as :default

    retry_on Sync::LockTimeout, wait: :polynomially_longer, attempts: 5
    # The cache committed. Do not rerun content replacement merely because
    # host external work failed; expose the discard through standard Rails logs
    # and instrumentation. Site indexing jobs own their own retries.
    discard_on Sync::AfterSyncError do |_job, error|
      ActiveSupport.error_reporter.report(error, source: "paradem_cms_site.after_sync")
    end

    def perform(context = {"source" => "webhook"})
      ParademCmsSite.refresh(context)
    end
  end
end
