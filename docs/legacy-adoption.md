# Migrate an existing application to one public gem

## Applications already using the extracted integration

1. Replace both gem declarations with one reviewed `dato_cms_graphql` 0.5.0
   public commit, using `require: "paradem_cms_site"`. Remove the private
   `paradem_cms_site` declaration and update the lockfile conservatively.
2. Keep existing `ParademCmsSite` constants, require paths, manifest, initializer,
   routes and serialized job names. The implementation now ships in the client;
   no wrapper gem, namespace migration or schema migration is necessary.
3. Verify installed wiring, locale/cache/query parity, preview isolation,
   authenticated enqueue-only webhooks and host callback behavior. Use synthetic
   content and disposable test databases, not a live sync as an installation test.
4. Remove private-gem-only `BUNDLE_GITHUB__COM`/`CMS_GEMS_BUNDLE_AUTH` injection,
   Docker build-secret mounts and deployment forwarding only after confirming no
   other dependency uses them. Keep unrelated deployment/CMS/search credentials.
5. Publish/merge the public ref before hosted consumer builds depend on it.
   Retain old private refs until deployed consumers no longer pin them. Never
   delete the only reachable ref for a lockfile SHA.

`ParademCmsSite::VERSION` follows `DatoCmsGraphql::VERSION`; there is one release
stream. Client-only/Bridgetown entry points and the legacy global loader are
unchanged. The Rails integration does not require that loader.

## Applications adopting the integration for the first time

Do not rerun the new-site installer over custom models. Adopt explicitly:

- Add manifest `rails` settings: `cache_model`, local `delivery_schema`, and
  `webhook: shared_header|hmac_sha256|disabled`.
- Require `paradem_cms_site/rails/installation` in the initializer and use
  `ParademCmsSite::Installation.new(root: Rails.root).configure!` in `to_prepare`.
- Include `ParademCmsSite::CacheRecord` in the dedicated cache base. Integer caches
  keep their historical `dato_cms_locale_mapping` before concern inclusion.
  Never infer positions from locale order or convert existing columns silently.
- Inherit owned query definitions from `ParademCmsSite::Query`. Preserve fields,
  fallback policies, computed permalink methods and manifest `permalink_fields`.
- Explicitly route `POST /webhooks/dato` to `paradem_cms_site/webhooks#create`.
- Verify the unique `(type, locale, cms_id)` index rather than automatically
  repairing a production cache during setup.

Keep site-owned indexes, generated files, notifications, preview clients and
external ingestion in host adapters. Configure `within_transaction(result,
context)` for same-database work, `after_sync(result, context)` for post-commit
work, and `on_error(error, context)` for diagnostics. External enqueue failure
must raise; it must not be reported as a rolled-back content transaction.

## Schema, boot and task boundaries

Loading Rails never constructs a content client. A local CDA snapshot supports
offline compilation/doctor. Only an explicitly invoked `cms:schema:snapshot`
writes it; `cms:sync:all` also snapshots during the full CLI lifecycle. These
commands contact DatoCMS and require separate operational authorization.

Legacy applications may explicitly enable `rails.allow_schema_introspection` for
invoked refresh/direct queries when a local snapshot is missing. Refresh client
construction stays inside coordination and outside the cache writer. An invalid
present snapshot fails; doctor never falls back to networking and still reports
a missing snapshot.

With `rails.boot_fallback: true`, a recoverable fetch/transport failure with a
warm cache retains rows and queues `RefreshJob` with `source: boot_retry`.
Cold caches and persistence/index errors still fail. Default behavior is strict.
`optional_singletons` allows only declared owned singleton nulls, never missing
keys, errors or incomplete collections.

- `cms:sync`: published content only, with `source: cli`.
- `cms:boot`: refresh under the configured boot-fallback policy.
- `cms:schema:snapshot`: CDA metadata only; no cache, generation or hooks.
- `cms:sync:all` / `sync:all`: export CMA schema for generated-query sites,
  snapshot CDA, generate/format owned queries, reload definitions, then refresh.
  Hand-authored queries are not regenerated or formatted.
- `cache_dato` / `dato_cms:cache`: aliases of `cms:sync` for installed applications.
  Keep any historical serialized job subclasses until old queues are drained.
- `cms:doctor`: read-only/offline diagnostics, not live acceptance.

Full CLI passes the management token through the DatoCMS CLI's supported
`DATOCMS_API_TOKEN` environment input, never argv or command logs. Export/format
failure stops before content refresh. `DATO_ENVIRONMENT` is the canonical
schema/delivery selector; legacy `DATO_SCHEMA_ENVIRONMENT` selects only the
snapshot when the canonical variable is blank.
