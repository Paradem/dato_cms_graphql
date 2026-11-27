# Optional Rails integration

Install with [one public dependency](installation.md), using
`require: "paradem_cms_site"` so Bundler loads the offline Railtie rather than the
legacy live-schema client. Models, routes, schemas and site policies remain
application-owned. Requiring the library never refreshes content or adds a route.

```ruby
require "paradem_cms_site/rails/installation"

Rails.application.config.to_prepare do
  ParademCmsSite::Installation.new(root: Rails.root).configure!
  ParademCmsSite.configure do |config|
    config.within_transaction = ->(result, context) { LocalIndex.rebuild! }
    config.after_sync = ->(result, context) { SiteIndexJob.perform_later(context) }
    config.on_error = ->(error, context) { SiteNotifier.report(error.class) }
  end
end
```

The hook classes above are examples, not generated services. `within_transaction`
is for same-database derived data; `after_sync` runs after commit. External search,
notifications and ingestion remain host-owned. An error-hook failure is reported
without masking the original error. See [refresh failure semantics](runtime-sync.md).

## Endpoint and authentication

Explicitly install the selected route:

```ruby
post "webhooks/dato", to: "paradem_cms_site/webhooks#create"
```

Manifest `rails.webhook` selects `shared_header`, `hmac_sha256` or `disabled`.
Installation reads `DATO_WEBHOOK_SECRET` at request time. Custom configuration can
supply a callable secret or header name:

```ruby
ParademCmsSite.configure do |config|
  config.webhook_authentication = ParademCmsSite::WebhookAuthentication.shared_header(
    secret: -> { ENV["DATO_WEBHOOK_SECRET"] }, header: "Webhook-Auth"
  )
  config.webhook_context = ->(request) { {"webhook_log_id" => SiteWebhookLog.accept!(request)} }
end
```

HMAC uses the raw request bytes and the default
`X-DATO-Signature: sha256=...` protocol. Both strategies reject blank/missing
secrets, missing/incorrect authentication, and use constant-time comparison.
No protocol downgrade or secret generation is performed.

Authentication runs before host context/log creation and enqueue. Requests do
not fetch CMS content. A small context hash is queued in
`ParademCmsSite::RefreshJob`; no token or payload archive is added by the gem.
`webhook_context` may return `nil` for an already handled event, or raise
`ParademCmsSite::WebhookRejected` for a host-owned 400 response. Hosts own event
validation, payload-hash idempotency and log retention.

Missing authentication returns 401; successful enqueue returns 200; enqueue
rejection returns 503. Context configuration errors are not silently accepted.
Use an asynchronous, production-appropriate ActiveJob adapter. File-backed
SQLite refreshes share database/table OS coordination across CLI, boot and jobs.

## Deployment-result notifications

A host that reports deployment results back to DatoCMS can use the shared
transport from its existing callbacks:

```ruby
config.after_sync = ->(_result, context) do
  ParademCmsSite::DeployNotifier.call(status: "success") if context["source"] == "webhook"
end
config.on_error = ->(_error, context) do
  ParademCmsSite::DeployNotifier.call(status: "error") if context["source"] == "webhook"
end
```

Set the owner-managed project endpoint as `DATO_DEPLOY_RESULT_URL` (or pass
`url:`); the URL path token is the authorization and belongs in secret
configuration, not source. The notifier requires HTTPS, applies explicit
open/read/write timeouts (five seconds by default, or `timeout:`), checks the
response status, and logs only the failure class or HTTP status — never the URL
or token. Missing configuration, non-2xx responses and transport failures return
`false` instead of raising, so notification trouble cannot turn a committed
refresh into a failed one. A blank URL is a logged no-op; do not call it if the
project does not use DatoCMS deploy results.

## Jobs and compatibility

`RefreshJob` retries `Sync::LockTimeout` with polynomial backoff, up to five
attempts. A committed-cache `Sync::AfterSyncError` is reported/discarded rather
than retrying content replacement. Host external jobs retain their retry policy.
Other exceptions follow normal ActiveJob behavior.

The `ParademCmsSite` controller/job constants and require paths are retained in
0.5.0 so existing routes and serialized job arguments need no renaming. There is
no separate `paradem_cms_site` gem to install. Existing integer/string locale
contracts, custom query selections, published-only transport and preview
isolation are unchanged. Do not infer a cache-column migration from a dependency
update. See [existing application migration](legacy-adoption.md).

`cms:doctor` validates local schema/query/cache/route/hook/queue wiring without
invoking hooks or fetching content. Production refuses synthetic fixture mode.
Only explicitly invoked refresh/snapshot/full-CLI tasks contact DatoCMS.
