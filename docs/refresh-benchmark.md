# Refresh scale benchmark

`benchmark/refresh.rb` measures the delivered published-cache path with authored
synthetic records. It does not contact DatoCMS, read host content, boot a web
server, start a queue, build indexes or measure production.

## Run

```sh
mise exec -- env ROWS=2895 PAYLOAD_KB=30 LOCALES=en \
  bundle exec ruby benchmark/refresh.rb

# Independent peak-RSS check on macOS:
mise exec -- env ROWS=2895 PAYLOAD_KB=30 LOCALES=en \
  /usr/bin/time -l bundle exec ruby benchmark/refresh.rb
```

Environment knobs:

| Variable | Default | Meaning |
|---|---|---|
| `ROWS` | `2895` | Published collection rows **per locale**. The default matches BIC's development-cache row count (count only; no content was read). |
| `PAYLOAD_KB` | `30` | Approximate filler per record. The default makes a ~100 MB one-locale cache, close to BIC's ~95 MB development database. |
| `LOCALES` | `en` | Comma-separated manifest locales; integer storage/mapping are generated. |
| `PAGE_SIZE` | `100` | GraphQL collection page size. |
| `CONCURRENCY` | `6` | Fetch worker bound passed to `Sync`. |

The script creates a disposable SQLite file and an in-process client. It reports
dataset size, database bytes, fetch/validate/materialize, delete/insert,
commit/callback and total sync durations, peak RSS (50 ms sampler), Ruby/
ActiveRecord/SQLite/platform information, and an explicit limits note.

## Reference run — 2026-11-13

Apple arm64, 12 processors, macOS 27.2.1, Ruby 4.0.9, ActiveRecord 8.1.4.1,
SQLite 3.54.1. In-process client; no provider latency or host callbacks.

| Dataset | Records | DB | Fetch ms | Replace ms | Commit ms | Total ms | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1,000 × 30 KB, EN | 1,001 | 34.9 MB | 97.5 | 275.3 | 87.5 | 460.4 | 294.3 MB |
| 2,895 × 30 KB, EN (run 1) | 2,896 | 100.9 MB | 285.0 | 795.5 | 201.2 | 1,281.8 | 751.1 MB |
| 2,895 × 30 KB, EN (run 2) | 2,896 | 100.9 MB | 290.4 | 775.7 | 170.8 | 1,237.1 | 741.4 MB |
| 2,895 × 30 KB, EN (run 3) | 2,896 | 100.9 MB | 283.4 | 802.1 | 175.1 | 1,260.7 | 697.1 MB |
| 2,895 × 30 KB, EN+FR | 5,792 | 201.8 MB | 564.5 | 1,587.9 | 406.1 | 2,558.6 | 1,323.1 MB |

`/usr/bin/time -l` on run 2 reported **777,814,016 bytes (741.8 MiB)** maximum
resident set, corroborating the sampler. The peak is roughly 7–8× the serialized
cache because response data, normalized candidate rows and SQLite insertion
representations coexist.

## Proposed budget (owner acceptance required)

The current Fly apps are configured with 2,048 MB (BIC) or 1,024 MB (Canada/CBNS).

- **BIC-sized, one locale:** propose peak RSS **≤ 1.5 GiB** and sync total
  **≤ 10 s** on comparable hardware. The reference run is ~0.74 GiB / ~1.26 s, so
  it would pass with memory/time headroom.
- **1 GiB hosts:** propose peak RSS **≤ 70% of configured memory (~717 MiB)** and
  total ≤ 10 s for each host's own authored row/payload mix. Do not apply the
  BIC-sized result blindly. At this synthetic 2-locale/30 KB size, measured peak
  (1.32 GiB) exceeds a 1 GiB container.
- Re-run when record count, average payload size, locale count, page size,
  concurrency, Ruby/ActiveRecord/SQLite version, container memory or host
  callbacks change. A budget is not a production performance certification.

Decision from this reference run: **no disk staging or insertion batching for the
BIC-sized 2 GB app now**. For 1 GiB EN/FR hosts, the current in-memory path is not
cleared by this synthetic result; measure the host's actual row/payload mix and
consider bounded staging/batching if it exceeds the proposed headroom. No runtime
change is made here.

## Limits

In-process client, no network/provider latency, retries or schema validation; no
host search/index/derived callbacks; one process and one SQLite file; peak sampler
may miss very short spikes (external OS time corroborates the reference run);
values vary with GC, disk and machine load. This is not a remote snapshot,
production benchmark, concurrency or availability test.
