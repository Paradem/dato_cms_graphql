# Install the optional Rails CMS integration

`dato_cms_graphql` 0.5.0 includes query tooling, cache synchronization, webhooks,
jobs and diagnostics. `ParademCmsSite` is the preserved API namespace, not another
gem. Rails 7.2–8.x supplies ActiveRecord, ActiveJob and ActionController; those
are not runtime dependencies for client-only or Bridgetown installations.

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
bin/rails generate paradem_cms_site:install --site=my_site --fixture --locales=en,fr --models=Page,Global --singletons=Global
bin/rails db:migrate
bin/rails cms:doctor
bin/rails cms:sync
```

For an enabled webhook, supply `DATO_WEBHOOK_SECRET` securely. Choose
`--webhook=hmac_sha256` or `--webhook=disabled` instead of the default
`shared_header` when appropriate. Fixture content requires no CMS token, makes
no HTTP requests and is rejected in production.

The installer generates only configuration, a dedicated cache model and owned
subclasses, lazy query definitions, an unapplied migration and the selected
route. `--cache-model=...` changes the default `CmsRecord` base. Fixture mode also
writes synthetic SDL/content under `config/cms/`. It does not copy services,
controllers, jobs, workflows, authentication helpers or custom scripts.

Use `--pretend` to preview. Identical reruns reuse the route/migration. Conflicts,
existing alternate webhook routes, invalid names and escaping/symlinked paths are
rejected before writes, even with `--force`. Do not use the installer as an updater
for customized applications; see [migration](legacy-adoption.md).

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
The installer currently accepts simple two/three-letter locale codes, not regional
GraphQL locale aliases.

## Diagnostics and commands

`cms:doctor` checks files, local query/schema validity, cache model/columns,
explicit locale mapping, identity index, hooks, route/auth configuration, queue
suitability and required environment-variable presence. It never syncs, invokes
hooks, creates a missing database, introspects, verifies live tokens or certifies
cache freshness. `cms-site doctor --root .` is the older filesystem-only check.

See [configuration/webhooks](rails-integration.md) and
[refresh semantics](runtime-sync.md) for callback and failure contracts.
