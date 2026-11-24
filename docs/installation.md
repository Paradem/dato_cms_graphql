# Install the optional Rails CMS integration

The `dato_cms_graphql` **0.6.0 candidate** includes query tooling, cache synchronization, webhooks,
jobs and diagnostics. `ParademCmsSite` is the preserved API namespace, not another
gem. The current unreleased candidate supports Ruby **4.0.10** and the latest
Rails **8.1** patch (currently **8.1.4.1**) only. Rails supplies ActiveRecord,
ActiveJob and ActionController; those are not runtime dependencies for client-only
or Bridgetown installations. See [supported versions and release policy](releases.md).
Older deployed refs retain their original requirements; do not repin a host that
has not qualified the new minimums.

## One dependency

Until an approved release is available, pin a reviewed public commit:

```ruby
gem "dato_cms_graphql", git: "https://github.com/Paradem/dato_cms_graphql.git",
  ref: "REVIEWED_PUBLIC_COMMIT", require: "paradem_cms_site"
```

The explicit require opts into the offline integration and its Railtie instead
of the legacy global client loader. Do not also declare `paradem_cms_site`.
Public Git checkout needs no private-gem credential or Docker build secret.
CMS runtime credentials and webhook authentication are still required for real content.

## Start offline

```sh
bundle install
bin/rails generate paradem_cms_site:install --site=my_site --fixture --locales=en,fr --models=Page,Global --singletons=Global --webhook=disabled
bin/rails db:migrate
bin/rails cms:doctor
bin/rails cms:sync
```

Webhooks now default to **disabled**. For an explicitly enabled
`--webhook=shared_header` or `--webhook=hmac_sha256`, supply `DATO_WEBHOOK_SECRET`
securely and configure the actual sender and an async job adapter. Fixture content requires no CMS token, makes
no HTTP requests and is rejected in production.

The installer generates only configuration, a dedicated cache model and owned
subclasses, lazy query definitions, an unapplied migration and the selected
route, operator notes and generator provenance. `--cache-model=...` changes the
default `CmsRecord` base. Fixture mode also
writes synthetic SDL/content under `config/cms/`. It does not copy services,
controllers, jobs, workflows, authentication helpers or custom scripts.

Use `--pretend` to preview. Identical reruns reuse the route/migration. Conflicts,
existing alternate webhook routes, invalid names and escaping/symlinked paths are
rejected before writes, even with `--force`; CLI errors return nonzero.
`config/cms/generators.json` records options/version and managed-input checksums.
Do not use the installer as an updater after resource generators or host edits
have changed its outputs; see [migration](legacy-adoption.md).

## Optional UI starters (unreleased source)

The separate `resource`, `block` and `theme` generators create host-owned
presentation and synthetic no-skip request/component/browser contracts. They do
not copy a shared renderer, registry or behavior catalogue. ViewComponent and the
host's Tailwind 4/Propshaft/importmap setup are explicit UI prerequisites, not new
client runtime dependencies. See [commands, ownership, CI and limits](generators.md).
The maintained fresh-app tests also build production assets and exercise actual
Chrome, including two independent host shells. [Local portability acceptance and
versioned upgrade/rollback policy](releases.md) keep hosted CI, publication and
per-host operational/accessibility release gates separate.

## Real content

Omit `--fixture`, supply the actual local CDA schema at `rails.delivery_schema`
(SDL `.graphql` or introspection `.json`), and customize the query fields/models.
The installer never fetches a schema, runs a migration or invents a live schema.

Configure `DATO_API_TOKEN`, optional `DATO_ENVIRONMENT`, and the selected sender's
`DATO_WEBHOOK_SECRET` through normal runtime secret management. `PROJECT` supplies
editing-link context. To leave fixture mode, remove `rails.fixture_data`, install
the real schema and review the starter queries. Reload/restart after schema changes.

The public cache is published-only. Boot/query-class loading is offline; query
compilation is lazy and uses the installation's client, not a global client.
Scoped `.all`, iterator indexing and singleton `.get` remain available.

For generated queries, set `generated_queries: true`, `schema_export` and
`overrides_path`, and supply a local CMA TypeScript export. That export is not
CDA introspection JSON. `queries:generate[Page]` accepts `DRY_RUN=1` or `FORCE=1`;
model ownership and all paths remain explicit in `config/cms_site.yml`.
The installer accepts simple (`en`) and regional (`en-US`) locale codes. Manifests
keep the declared spelling; query aliases, `SiteLocale`/fallback arguments and
the generated fixture schema use the underscored GraphQL form (`en_US`), which
matches DatoCMS's enum. Locales that collide after normalization are rejected.

## Diagnostics and commands

`cms:doctor` checks files, local query/schema validity, cache model/columns,
explicit locale mapping, identity index, hooks, route/auth configuration, queue
suitability and required environment-variable presence. Every statically declared
controller/action target must resolve to an implemented public action, including
host-owned optional capabilities. Removing a disabled capability's route removes
it from this check; a route declaration alone is not an implementation. Callable,
mounted and dynamically selected targets still need host-specific checks, and
hosts must request-test their enabled endpoints and authorization behavior.

Doctor never dispatches route actions, syncs, invokes hooks, creates a missing
database, introspects, verifies live tokens or certifies cache freshness.
`cms-site doctor --root .` is the older filesystem-only check.

See [configuration/webhooks](rails-integration.md) and
[refresh semantics](runtime-sync.md) for callback and failure contracts.
