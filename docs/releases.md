# Compatibility, portability and release policy

**2026-11-24: local source qualification, not a published release.** The gem
version remains **0.5.0**; generator additions/default changes are **unreleased**.
This follows the coordinating project's **Rails + DatoCMS recipe v1**. Publication,
tags, host repins, CMS operations and deployment require separate owner approval.

## Supported surfaces

| Surface | Policy / qualified boundary |
|---|---|
| Public client | MRI Ruby **>= 3.2**; declared ActiveSupport **>= 7.1, < 9**; `graphql-client ~> 0.23.0`, `ostruct`, `logger`. Rails/UI/browser dependencies remain optional. |
| New Rails installation/generators | Rails **7.2, 8.0, 8.1** with matching framework components; SQLite **2.x** (`>= 2.1, < 3`). Older Rails, Rails 9, alternate Ruby engines and other database adapters are not fresh-site qualified. An admitted dependency range is not proof of every combination. |
| Host UI starter | ViewComponent **4.x**, Propshaft **1.x**, importmap/Turbo **2.x**, Tailwind Rails **4.x** / Tailwind CSS **4.x**. Not Tailwind 3, a JS bundler migration or a shared UI engine. Existing hosts can keep their own presentation/adapters. |
| Browser qualification | Actual Chrome; Selenium **4.41.x** for the Ruby 3.2-compatible development matrix, Capybara **3.40.x**, axe-core-capybara **4.11.x**, Puma **>= 8.0.4, < 9**. These are development/test dependencies, not client runtime requirements. Other browsers need separate qualification. |

Rails **7.2/8.0 require JSON 2.x** in these qualified bundles: their encoder passes
`quirks_mode`, which JSON 3 removed. A host on those framework lines must declare
`gem "json", "~> 2.0"` and review its lock; do not monkey-patch encoding or apply a
global JSON cap to Rails 8.1. The alternate development Gemfiles make this explicit.
Likewise newer Selenium releases can require Ruby 3.3; do not copy a newer-Ruby
browser lock into a Ruby 3.2 project without checking it.

Use currently security-supported, patched Ruby/framework/dependency versions in
production. Older interpreters below are compatibility fixtures, **not** an EOL or
security endorsement. Raising a minimum/removing a supported line is a versioned,
reviewed change. ActiveSupport 7.1's client dependency allowance does not qualify
Rails 7.1 UI generation. Recheck compatibility and advisories whenever a lock moves.

### Executed local matrix

All six lanes below ran the **entire** core/site suites, generated request/component
and actual browser tests, production assets and credential-free eager boot on
macOS ARM64. Every lane: core **42 / 299**, site **129 / 1205**, zero
failures/errors/skips. No reduced smoke or missing-browser skips substitute for a lane.

| MRI | Rails | JSON | Dependency lock |
|---|---|---|---|
| 3.2.9 | 8.1.4.1 | 3.1.0 | `Gemfile.lock` |
| 3.3.8 | 8.1.4.1 | 3.1.0 | `Gemfile.lock` |
| 3.4.5 | 8.1.4.1 | 3.1.0 | `Gemfile.lock` |
| **4.0.10** (development default) | 8.1.4.1 | 3.1.0 | `Gemfile.lock` |
| 3.2.9 | 7.2.3 | 2.21.2 | `gemfiles/rails_7_2.gemfile.lock` |
| 4.0.10 | 8.0.5.2 | 2.21.2 | `gemfiles/rails_8_0.gemfile.lock` |

All use ViewComponent **4.24.0**, Propshaft **1.3.2**, importmap-rails **2.2.3**,
turbo-rails **2.0.23**, tailwindcss-rails **4.7.0**, Tailwind **4.3.4**, Puma **8.0.4**,
Selenium **4.41.0** and Chrome **157**. Exact resolutions/platforms live in the
committed locks; the alternate locks preserve unrelated baseline versions.

```sh
BUNDLE_FROZEN=true bundle install
SE_SKIP_DRIVER_IN_PATH=true bundle exec rake test
bundle exec standardrb
# Minimum-framework lane, using its intended Ruby interpreter:
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile BUNDLE_FROZEN=true bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile SE_SKIP_DRIVER_IN_PATH=true bundle exec rake test
# Repeat with gemfiles/rails_8_0.gemfile for the intermediate-framework lane.
gem build dato_cms_graphql.gemspec --output /tmp/dato_cms_graphql.gem
```

Ubuntu 24.04 CI is configured for the same six Ruby/framework lanes and artifact
upload, but **hosted/Linux execution was not performed for this source change**.
Neither that configuration nor local macOS results qualify production images.

## What fresh-site portability proves

`test/site/rails_portability_test.rb` generates two independent temporary Rails
applications from the same commands and original synthetic fixtures. Their
reviewable source is byte-identical, normalizing **only migration timestamp
filenames**. Both theme imports coexist; identical theme reruns preserve bytes;
`--force` refuses host customization before writing anything. Existing scaffold
safety tests retain pretend, interrupted/conflicting wiring and path coverage.

The first application then renders the same localized cache IDs and generated
Article/Promo components through two deliberately host-edited shells:

- **Journal:** warm light surface, centered masthead/footer and serif typography.
- **Folio:** dark surface, sans-serif typography and a responsive desktop side rail.

Only the disposable host's layouts/CSS/controllers/views differ. There is no gem
renderer change, runtime theme registry, commercial snippet or cross-host theme
interchangeability promise. The original fixture layouts live under
`test/site/fixtures/portability`, are not generator templates and are not packaged.

The two-shell app runs **7 request/component tests / 50 assertions** and **3 actual
browser tests / 320 assertions**. The shared browser contract covers EN/FR × exact
**390×844 / 1280×900**, cache identity, long titles, absent optional body, computed
colors/fonts/layout, horizontal overflow, keyboard skip/focus/disclosure behavior,
Turbo locale navigation and cached-history restoration. Real fixture refresh seeds
the prepared test DB; a pre-test process's cache is not assumed to survive Rails'
test-schema preparation. Production CSS contains both shells and component utilities.

Each lane retains **16 two-shell axe scans** plus **8 resource scans**, all with
zero violations/incompletes; the earlier one-theme pilot adds **12** scans. There
are no rule/node exclusions. Complete JSON/screenshots and nonsecret Ruby/platform/
package versions are retained in `tmp/{generator,portability}-evidence/<ruby>/<rails>/`.
Evidence is local/untracked, not a packaged application or content backup. Review
real fonts/content, screen readers, zoom and every incomplete manually before release;
automatic scans and screenshot inspection are not WCAG certification.

### Refresh and rollback proof

The disposable application's safety probe enqueues the real `RefreshJob`, checks
that enqueue leaves a cold cache empty, then executes the queued job to populate
eight rows, including slug projections. It verifies:

- failed delivery preserves the entire last-good cache;
- strict boot fails; explicitly opted-in warm fallback queues `boot_retry`;
- cold boot still fails, with no empty-cache fallback;
- a same-database derived-index exception rolls back both candidate cache and
  derived marker, is not treated as a recoverable delivery failure, and queues no retry.

A second probe backs up a coherent SQLite database with `VACUUM INTO`, changes
synthetic schema/query/data to a valid candidate and refreshes it, then injects an
invalid query. Doctor rejects the query without changing that candidate cache.
After all subprocesses exit, restoring the matched source/schema/query/database
set recovers the original digest and doctor; the browser then renders the restored
content. This is **host-artifact cutback**, not an actual gem-version downgrade,
remote CMS schema rollback or distributed transaction. The production preparation
rollback remains covered by the existing artifact-set tests. A failure in
`after_sync` occurs **after commit**: do not mistake it for a rolled-back swap or
retry the whole content replacement just to repeat a notification.

## Versioning and upgrades

1. **One public distribution.** `dato_cms_graphql` owns the runtime and preserved
   `ParademCmsSite` API; never resurrect a private wrapper/authentication dependency.
   Pin an immutable reviewed public commit for unreleased source. A branch name or
   unchanged `0.5.0` version alone does not identify these additions.
2. **Version intentional changes.** Record behavior/default/dependency/generator
   changes in the changelog and release notes. While pre-1.0, additive features and
   breaking defaults/API/cache/query/job/locale changes require a reviewed minor
   release; compatible fixes use a patch. The new generators/disabled-webhook
   default need a future minor release, not silent replacement of the 0.5.0 tag.
   A future 1.0 additionally needs explicit compatibility/support commitments;
   this local milestone does not declare 1.0 or production stability.
3. **Generated files belong to the host.** Provenance records generator version,
   options and checksums, not an application updater. Upgrade templates by reviewing
   a freshly generated scratch app and merging the needed host diff manually.
   Never rerun install or use `--force` to erase customizations. Do not redistribute
   private payloads, credentials, runtime databases or commercial markup.
4. **Qualify a candidate without live writes.** Record host/code/gem ref, lock,
   schema/export/override/query digests, locale mapping, cache shape and derived
   data hooks. Run doctor, offline contracts, both shells, exact viewports, axe,
   assets/eager boot and all supported CI lanes. Review package allowlist, advisory
   results and real worker/queue/image/memory/accessibility requirements. No missing
   lane or unresolved manual gate becomes green by omission.
5. **Approve separately.** Hosted CI/Linux results, release version/tag/publication,
   each host pin/migration and deployment are independent approvals. Verify fetch
   and push remotes before any approved push; the coordination repository is not
   the gem repository. Local tests never authorize publishing, CMS content/schema
   changes, credentials, queue/provider operations or deployment.
6. **Retain a matched rollback set.** Save the previous host commit, immutable gem
   ref/lock, schema/export/overrides/queries and a consistent database/derived-data
   backup. Stop/drain the intended host's writers/jobs under an approved cutover;
   use SQLite backup/VACUUM or a supported storage snapshot, **not a live DB-file
   copy without WAL**. Restore compatible code/artifacts/cache together, restart,
   run doctor and verify published routes/freshness/derived indexes before resuming
   jobs. Do not drop private tables, reapply historical migrations or replay CMS
   content/publication as a side effect. External indexes/notifications and an
   incompatible remote schema require their own approved recovery plan.
