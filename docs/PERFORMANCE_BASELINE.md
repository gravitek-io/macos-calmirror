# Activity log I/O baseline

Measured with the opt-in `SyncLogPerformanceBenchmarks` release test on Apple
Silicon, macOS 27.2, using seven samples per read/append operation. Fixtures
contained synthetic `SyncLog` entries with empty change/error arrays and
timestamps within the 30-day retention window. These values isolate JSON and
file costs; real log entries with many changes will be larger.

## Before revision-aware polling

| History | Fixture bytes | Full load p50/p95 | Poll read p50/p95 | Latest-by-rule p50/p95 | Append p50/p95 | Six-rule rewrite estimate |
|---:|---:|---:|---:|---:|---:|---:|
| 1k | 287,002 | 5.57 / 5.99 ms | 5.42 / 5.48 ms | 5.56 / 5.58 ms | 12.67 / 12.95 ms | 1.72 MB |
| 17k | 4,879,002 | 92.82 / 93.78 ms | 93.28 / 96.37 ms | 94.05 / 97.09 ms | 210.63 / 217.52 ms | 29.27 MB |
| 100k | 28,700,002 | 544.49 / 551.39 ms | 541.13 / 583.28 ms | 556.17 / 561.72 ms | 1,251.97 / 1,400.47 ms | 172.20 MB |

The six-rule estimate multiplies the starting JSON size by six, assuming each
rule appends one activity entry and the current JSON store rewrites the retained
array each time. It is a byte-volume estimate, not a direct filesystem counter.

## After revision-aware polling

The same benchmark now primes a poll snapshot, then repeats unchanged polls
using the atomic log revision. Read and append measurements remain within normal
run variation; the repeated poll avoids JSON decoding:

| History | Full load p50/p95 | Unchanged poll p50/p95 | Latest-by-rule p50/p95 | Append p50/p95 | Seven appended bytes |
|---:|---:|---:|---:|---:|---:|
| 1k | 5.72 / 6.26 ms | 0.09 / 0.12 ms | 5.70 / 5.73 ms | 12.89 / 13.73 ms | 1,988 B |
| 17k | 94.69 / 96.50 ms | 0.08 / 0.15 ms | 93.69 / 98.11 ms | 215.71 / 218.23 ms | 1,988 B |
| 100k | 551.00 / 558.40 ms | 0.09 / 0.26 ms | 575.99 / 616.33 ms | 1,248.44 / 1,267.67 ms | 1,988 B |

Revision-aware polling reduces the unchanged poll path to a metadata check. Full
history reads still serve the initial load and refresh after a sync. Appends
still rewrite the JSON history, with the measured costs above; for the current
estimated 17k retained entries this is about 216 ms per appended rule log and
approximately 29.3 MB written across a six-rule sync. This cost is measurable,
but changing the on-disk format would add migration/recovery risk; keep JSON for
now and revisit if production histories or sync durations materially grow.

Reproduce with:

```sh
CALMIRROR_RUN_LOG_BENCHMARK=1 swift test -c release --filter SyncLogPerformanceBenchmarks
```
