# Host-owned Rails generators (unreleased source)

The optional `ParademCmsSite` integration provides `install`, `resource`, `block`
and `theme`. These are new-site starters, not an application updater, shared UI
engine or block catalogue. The runtime remains in this public gem; generated
models, queries, controllers, components, routes and shells belong to the host.
No generator contacts CMS, applies a migration, publishes content or deploys.

## Small offline example

Start in a Rails application with ViewComponent, Propshaft, importmap and
Tailwind **4** installed normally. Keep the host's existing Hotwire setup.
Client-only users do not need any of these dependencies. Add Capybara, Selenium,
Puma and `axe-core-capybara` to the application's test dependencies for browser
contracts. Nothing edits the application's Gemfile or installs another gem.

```sh
bin/rails generate paradem_cms_site:install \
  --site=example --fixture --locales=en,fr \
  --models=Page,Global --singletons=Global --webhook=disabled
bin/rails generate paradem_cms_site:theme journal
bin/rails generate paradem_cms_site:resource Article \
  --body=body --permalink=slug --fallback-locale=none --theme=journal
bin/rails generate paradem_cms_site:resource Home --singleton --theme=journal
bin/rails generate paradem_cms_site:block promo --layout=wide
# Review before explicitly migrating this application's local cache:
bin/rails db:migrate
bin/rails cms:doctor
bin/rails cms:sync
bin/rails tailwindcss:build
bin/rails test
bin/rails test:system
```

Installation now defaults to **disabled webhooks**. Enable `shared_header` or
`hmac_sha256` explicitly only after configuring its sender, secret and async job
adapter. Other optional capabilities are not invented or enabled. Fixture mode
uses synthetic local content, needs no CMS token and is rejected in production.
See [installation](installation.md) for real-schema and credential preparation.

## Resource

`resource Article` creates an STI subclass of the declared cache, lazy query,
`Site::ArticleComponent`, `Site::ArticlesController`, page template, host path
helper, synthetic JSON and required request/component/system tests. Its deliberately
namespaced starter URL is **`/cms/:locale/articles/:permalink`**; a singleton uses
`/cms/:locale/homes`. This is not a promised production URL or a catch-all route.
Review the helper/routes before choosing canonical or legacy public URLs.

- `--permalink=slug` explicitly projects that query output key into the cache's
  `permalink` column. The helper/controller use the cache projection, not a raw
  CMS slug assumption. Locale lookup and `render: true` are enforced; unsupported
  locales or absent/unrenderable records return 404.
- `--body=body` is an **optional plain-text starter**, escaped like the title.
  Null titles fall back to the model's localized human name rather than an empty
  heading. No raw HTML, Markdown/DAST renderer or universal domain model is generated.
  Rich text, block traversal and domain-specific paths remain host integration.
- `--fallback-locale=none` emits `fallback_locale :none` **before** compilation;
  other values must be declared locales. Singleton behavior is explicit.
- `--theme=journal` selects an existing generated shell. No global layout changes.
- Adding a model updates explicit manifest ownership. Only checksum-matched,
  generated **synthetic SDL/JSON** is extended. Real snapshots, CMA exports and
  historical migrations are never rewritten or fetched. Real schema additions
  must precede queries that depend on them; run doctor before a live refresh.

For `generated_queries: true`, prepare the owned model in the local CMA export
and its override entry first. The resource delegates to the maintained query
builder in dry-run mode; it does not rewrite overrides. Unknown/conflicting keys,
unavailable models, inconsistent singleton/fallback flags and missing or
mismatched scalar projections fail before writes. Use output/alias names for the cache
projection. Existing customized model/query files are not overwritten, even if
they would otherwise be valid domain adapters; merge those deliberately.

## Custom block

`block promo --layout=reading|wide|section` creates `Site::Blocks::Promo`, a
ViewComponent template, synthetic fixture, component test and integration notes.
The default constructor is `resource:` for the reviewed DAST module-dispatch API;
it accepts Hash/OpenStruct envelopes and escapes title/body text. The generated
wrapper owns its gutters. Constructors/markup are host-owned after generation.

Supply `component_module: Site::Blocks` to the host's existing
`DastDocument::Document` integration if using that API. No registration table,
CMS validators, body-field membership, root query or publication is inferred.
Existing walkers can retain their own adapters. New templates use `.html.erb`;
a single existing matching `.erb` target is reused, while ambiguous dual templates
or customized files stop the generator.

## Theme

`theme journal` creates scoped tokens, a complete host layout, EN/FR synthetic
preview labels, a public preview controller/page, required request/system tests,
operator notes and a standalone `cms-fixtures.yml` CI skeleton. Its preview URL is
**`/cms/themes/journal/:locale`** and never reads CMS rows or contacts a provider.
The theme is not activated on other pages automatically.

CSS tokens/font placeholders are host-owned and contain no remote font/logo or
provider data. Tailwind imports the theme and explicitly scans host components
**and views**, including with `source(none)`. Multiple theme files can coexist.
The layout uses the host's importmap; native links/details need no new JavaScript
or pins, so no Stimulus controller is copied or forked. All starter markup is
original, not redistributed commercial Tailwind Plus snippets.

Supported regional locale spelling is retained in routes/cache/configuration;
HTML `lang`/`hreflang` converts underscores to standard hyphens. EN/FR fixture
copy is supplied; translate other declared locales before editorial release.

## Ownership, conflicts and reruns

`config/cms/generators.json` records generator versions/options and SHA-256 values
for shared tool-owned inputs. It is local provenance, not authorization to change
remote CMS ownership. Manifest queries remain the actual runtime allowlist.

- `--pretend` previews without writing destination files or creating a database.
- Identical reruns are byte-identical and do not duplicate routes, migrations,
  CSS imports/sources or pins. The installer is not rerun to update a site after
  other generators have extended its manifest; review upgrades separately.
- Preflight validates **all** outputs before any write. Customized files,
  conflicting routes/options, malformed provenance and outside/dangling symlinks
  fail closed, including with `--force`. CLI errors return a nonzero exit status.
- Shared generated fixtures/manifest updates require matching recorded checksums.
  Host CSS/route edits are limited to explicit import/source/route insertion;
  unrelated bytes are retained; removed/customized recorded wiring stops a rerun
  rather than silently reenabling it. No private database/dump/credential is inspected
  or copied. `destroy` refuses to remove host-owned output.
- Writes use ordinary Rails file actions, **not an OS transaction**. Inspect an
  interrupted run before retrying; do not force away a conflict to hide it.

Commit the reviewed generated files, ownership metadata and an **unapplied** cache
migration together. Keep the previous compatible code/query/schema/cache set for
rollback; generation is not permission to run DB/CMS migrations or deploy.

## Required checks and limits

The opt-in `paradem_cms_site/testing/system_test_case` is test-only and is never
loaded by the production Railtie/client. It enforces loopback-only Ruby HTTP,
blocks browser external DNS, asserts exact 390×844/1280×900 CSS viewports and runs
all configured locales without content-dependent skips, including long resource
page fixtures. A host-owned layout must supply the correct HTML language and
accessible structure; use a generated theme or adapt the existing shell rather
than skipping a failing locale. Actual axe scans have
no rule/node exclusions; complete JSON (including incompletes) and screenshots
are retained as CI artifacts. A missing browser, driver or fixture is a failure,
not a skip. `SE_SKIP_DRIVER_IN_PATH=true` lets Selenium Manager avoid an obsolete
PATH driver; an explicit compatible `SE_CHROMEDRIVER` also works.

Generated request/component tests use synthetic data in the test database and
cover routing, locale rejection, renderability, escaping and missing
optional fields. The maintained fresh-app test exercises all generators,
reruns/pretend/conflicts, doctor/fixture sync, these tests, actual Chrome and a
credential-free production eager boot/asset build. It is not a CMS migration,
full production-image qualification or a release compatibility promise.

Manually review real fonts/content, keyboard/screen-reader/zoom behavior, contrast
and every incomplete axe result before release. No WCAG certification, provider
integration, external search backend, hostile-CMS certification or production
approval follows from a green generated test suite. Two materially different
fresh-site themes and supported upgrade/release policy remain a separate
portability milestone.
