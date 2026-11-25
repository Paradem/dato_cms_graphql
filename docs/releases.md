# Compatibility, portability and release policy

**2026-11-25: 0.6.0 released.** Tag `v0.6.0` (source `d1e750f`) carries the built
gem on the GitHub release; it is not published to RubyGems.org. The candidate
includes generator additions, disabled-webhook defaults and new Ruby/AS minimums.
This follows the coordinating project's **Rails + DatoCMS recipe v1**. Publication,
tags, host repins, CMS operations and deployment require separate owner approval.

## Supported surfaces

| Surface | Policy / qualified boundary |
|---|---|
| Public client | MRI Ruby **4.0.10**; ActiveSupport **8.1.x**, at least **8.1.4.1**; `graphql-client ~> 0.23.0`, patched `graphql >= 2.6.16, < 3`, `ostruct`, `logger`. Rails/UI/browser dependencies remain optional. |
| New Rails installation/generators | Latest **Rails 8.1** patch with matching framework components; currently **8.1.4.1**. SQLite **2.x** (`>= 2.1, < 3`). Older Rails/Ruby, alternate Ruby engines and other adapters are not supported by this candidate. |
| Host UI starter | ViewComponent **4.x**, Propshaft **1.x**, importmap/Turbo **2.x**, Tailwind Rails **4.x** / Tailwind CSS **4.x**. Not Tailwind 3, a JS bundler migration or a shared UI engine. Existing hosts can keep their own presentation/adapters. |
| Browser qualification | Actual Chrome; current Selenium **4.x**, Capybara **3.40.x**, axe-core-capybara **4.x**, Puma **>= 8.0.4, < 9**. These are development/test dependencies, not client runtime requirements. Other browsers need separate qualification. |

**Owner decision, 2026-11-24:** support only Ruby **4.0.10** and the latest Rails
**8.1** patch. The gem requires Ruby `~> 4.0.10` and ActiveSupport `~> 8.1.0,
>= 8.1.4.1`; admitting future patches does not replace qualification. Older
compatibility lanes/bundles, JSON 2 workarounds and the Ruby 3.2-driven Selenium
restriction are removed. This is a breaking minimum change for the next minor
release, not a change to already pinned 0.5.0 hosts. Recheck support/advisories and
rerun the one supported job whenever a patch or lock moves.

### Qualification

Run the **entire** core/site suites, generated request/component and actual browser
tests, production assets and credential-free eager boot on Ruby **4.0.10**, Rails
**8.1.4.1**, using `Gemfile.lock`. No reduced smoke or missing-browser skips
substitute for this job. Current resolutions include GraphQL **2.6.16**, JSON
**3.1.0**, Selenium **4.54.0**, ViewComponent **4.24.0**, Propshaft **1.3.2**,
importmap-rails **2.2.3**, turbo-rails **2.0.23**, tailwindcss-rails **4.7.0**,
Tailwind **4.3.4** and Puma **8.0.4**.

The former six-lane local proof at source `942e9ee` remains historical evidence,
not an ongoing support commitment. The narrower candidate is qualified through
[PR #19](https://github.com/Paradem/dato_cms_graphql/pull/19); record its exact
successful head/run before release. The narrowed pre-version-bump source `afae539`
passed [hosted Ubuntu/Chrome run 45452396212](https://github.com/Paradem/dato_cms_graphql/actions/runs/45452396212),
including all tests, advisory check, lint, package build and artifact upload. Its
36 downloaded axe reports have zero violations/incompletes. The final 0.6.0 head
must also pass; a prior green head does not qualify a changed candidate.
On macOS ARM64 the narrowed candidate passes
core **42 / 299**, site **129 / 1214**, generated two-shell app **7 / 50** and browser
**3 / 320**, with no failures/errors/skips. The updated advisory scan reports zero
findings after GraphQL **2.6.14 → 2.6.16**; no advisory is ignored.

```sh
BUNDLE_FROZEN=true bundle install
SE_SKIP_DRIVER_IN_PATH=true bundle exec rake test
bundle exec standardrb
bundle exec bundle-audit check --update
gem build dato_cms_graphql.gemspec --output /tmp/dato_cms_graphql.gem
```

Ubuntu 24.04 CI has **one** Ruby 4.0.10 / Rails 8.1 job, including current advisory
checks and artifact upload. A configured job is not a successful hosted run, and
neither a green job nor local macOS results qualify existing hosts' production images.

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

Each supported run retains **16 two-shell axe scans** plus **8 resource scans**, all with
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
   breaking minimums/defaults/API/cache/query/job/locale changes require a reviewed minor
   release; compatible fixes use a patch. The new generators/disabled-webhook
   default are released as 0.6.0, not silent replacement of 0.5.0.
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
   assets/eager boot and the supported CI job. Review package allowlist, advisory
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
