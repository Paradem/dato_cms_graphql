# Published cache synchronization

`require "paradem_cms_site/sync"` loads the explicit refresh service without
booting Rails, loading a host client or contacting DatoCMS.

```ruby
manifest = ParademCmsSite::Manifest.load(root: Rails.root)
result = ParademCmsSite::Sync.new(
  manifest: manifest,
  queries: [PageQuery, GlobalQuery], # Exactly the manifest's owned queries.
  client: published_client,
  environment: ENV["DATO_ENVIRONMENT"],
  record_class: Record,
  within_transaction: ->(_result) { LocalSearchIndex.rebuild! },
  after_sync: ->(_result) { SiteIndexJob.perform_later }
).call
```

The named client/index/job implementations are host-owned examples. Hooks are
optional. Search infrastructure, extraction, preview authorization and themes
are not part of this gem.

## Lifecycle

1. Reject an already-open cache transaction. Acquire coordination before client
   construction/fetch. File-backed SQLite derives a database/table-scoped OS file
   lock; other backends require an explicit `coordinator:` implementing
   `synchronize`. The lock covers fetch through the post-commit callback, without
   holding SQLite's writer during HTTP or lock waits. Process death releases it.
2. Fetch published counts, pages and singletons with bounded concurrency
   (default six workers), always passing `include_drafts: false`. Real GraphQL
   HTTP clients must omit draft headers and match the explicit environment;
   validated headers are snapshotted without changing globals/source transports.
3. Validate all locale keys, counts, shapes, IDs, uniqueness, collection totals
   and required singletons. Reject nested GraphQL errors and partial data.
   Valid empty collections differ from missing data. Only explicitly declared
   `optional_singletons` may return null.
4. On the calling thread, replace rows and run `within_transaction` in one
   database transaction. Fetch/validation/insertion/local-index failure leaves
   the last-good cache intact. An explicit `ActiveRecord::Rollback` raises
   `Sync::TransactionError`, not success. Derived tables must use the same DB.
5. After commit, run `after_sync` with a frozen result (`site`, `record_count`).
   It never runs following fetch/validation/transaction failure.

Use only a dedicated CMS cache base model, never a domain table or STI subclass:
replacement deletes its rows. Expected columns are `type`, `locale`, `cms_id`,
`render`, `permalink`, `cms_record`; insertion uses ActiveRecord bulk insertion
and bypasses model callbacks. Database constraints still apply. Locale storage
comes from the explicit manifest mapping; permalink projections are explicit.

`Sync::AfterSyncError` means **the content committed but host work failed**.
Its `result` identifies the committed refresh and `cause` is the callback error.
Retry external indexing separately, not by automatically replacing content again.
Prefer enqueueing a host job with its own retry policy. No exactly-once delivery
or point-in-time remote CMS snapshot is promised.

For lazy client construction, `client:` may be a callable; it runs after the
coordinator is acquired. All writers must participate in the same coordination
protocol. File locks do not coordinate independent volumes.

See [Rails configuration and webhooks](rails-integration.md) and
[installation](installation.md). Loading/installing never authorizes a live
refresh, management operation or deployment.
