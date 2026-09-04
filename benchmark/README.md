# hintful benchmarks

The benchmark runs hintful through the **flutter_bench_contract** package:
one neutral scene, contract scenarios S1–S7 with a single protocol per
metric. The consumer code is deliberately thin — a driver mapping the
scenario verbs onto hintful's real API — while the scenarios, collectors,
golden store and gate live in the package. Reference values live in
`benchmarks.json` (shared store) and are enforced by the `bench-core`
dispatch on a profile emulator.

## Layout

The benchmark is its own package (sibling of `example/`) because its scene
deliberately does not use the example app — the example's bootstrap would
leak into the numbers and needs plugins that VM runs don't have.

- `bench/contract/` — the generated per-scenario bridges (~8 lines each:
  register one scenario body with the driver). The bodies themselves live
  in the package (`lib/scenarios.dart`) — consumers cannot edit the
  measurement, only supply a driver. Do not edit; regenerate: `contract
  init --force`;
- `bench/drivers/hintful_driver.dart` — **the only hintful-specific code**:
  builds the neutral scene with hintful's `HintTarget`s and maps
  `show/update/hide` onto `HintController`;
- `bench/startup_to_show_test.dart` — hintful's own frame-count scenario,
  registered in the manifest under `customScenarios:`: its own metric and
  golden ref, outside S1–S7, excluded from the head-to-head comparison and
  the public tables;
- `bench_contract.yaml` — the consumer manifest (library, scenarios,
  driver, S7 `size:` section);
- `lib/main.dart` / `lib/main_baseline.dart` — entry points with/without
  hintful, the S7 size targets;
- no runner script — the `bench-core` dispatch (`.github/workflows/
  bench-core.yml`) calls the contract CLI directly (device scenarios +
  the native size leg + the metrics card);
- `bench_contract.yaml` `card:`/`readme:` sections — hintful's marketing
  copy for the published results; the MACHINERY (card widget, table
  renderer, fonts, formatting) lives in the contract package (`contract
  card` / `contract readme`);
- `compare/` — a second consumer (bench_compare): the same contract
  scenarios driven through showcaseview / tutorial_coach_mark, recording
  into the same store under refs `android-scv` / `android-tcm`.

## Metrics (S1–S7)

The contract measures interaction scenarios, not tooltip classes — the
definitions are fixed in the package and identical for every consumer.
Device metrics (profile emulator, ref `android` for hintful):

| Scenario | Metric | What it answers |
|---|---|---|
| S1 idle_zero | tree-diff with vs without the library, nothing shown | no idle tax per screen |
| S2 show_latency | wall-ms from `show()` to a stable, visible tooltip | cost of showing |
| S3 update_latency | wall-ms of a step/content change on an active tour | cost of updating |
| S4 scroll_coupled | two-sided assert: content follows the anchor under scroll | correctness + perf |
| S5 active_heap | retained heap idle → active step | active-step weight |
| S6 hide_retention | heap drift per show/hide cycle + tree back to idle | leaks after hide |
| S7 size | host builds: native AOT + web bundle delta | bundle footprint |

S4 and S1r are in-scenario asserts / diagnostics — they record no number
(see the footnote under the root README table). Frames collected during
S2/S3/S4 are diagnostics, not gated: the contract's primary metrics are
wall-latency and heap, because software-rendered emulator frame numbers
are noise.

Reference values (Flutter 3.47.0, API 36 x86_64 emulator, recorded
2026-09-03): `idle_zero=4`, `show_latency=72 ms`, `update_latency=66 ms`,
`active_heap=41632 B`, `hide_retention=539 B`. Re-record with the
`bench-core` workflow's `record` input — the reference for check runs is
the same API 36 image.

## Running

VM sanity (fast, CI-friendly, no device — heap scenarios print
"degraded"/null where the VM service is unavailable). A full
`contract run` also builds the S7 legs, so for a quick host check select a
subset:

```bash
cd benchmark
flutter test bench/                        # contract scenarios + startup
dart run flutter_bench_contract:contract run --scenarios idle_zero --mode check
```

Device (profile emulator — the whole manifest, size legs included):

```bash
dart run flutter_bench_contract:contract run --device <id> --mode check    # gate
dart run flutter_bench_contract:contract run --device <id> --mode record   # record
# full publish flow (device scenarios + the native size leg + the card):
cd benchmark && dart run flutter_bench_contract:contract run --device emulator-5554 --mode record --ref android --legs native
cd benchmark && dart run flutter_bench_contract:contract card
```

The `bench-core` workflow job runs exactly these two commands inside the
emulator step (record or check): `contract run` drives the device contract
scenarios via `flutter drive --profile --no-dds` and the S7 native size leg
(`--legs native`; the web leg stays in the plain-CI bundle job) in the same
invocation, then `contract card` renders the metrics-card PNG on the host
from the recorded goldens (the PNG lands at `../docs/hint_metrics.png`),
checking/recording against `benchmarks.json`. A record dispatch also
re-renders the root README "Performance" section (`contract readme`: one
table from the store + the card PNG, between the bench markers) and commits
it.

Regenerate the scenario files after a template bump:

```bash
dart run flutter_bench_contract:contract init --force
```

## Size (S7)

S7 is a scenario like the rest — one `contract run` invocation runs the
manifest's declared scenarios plus the host release size builds (no
device). The manifest's `size:` section declares the legs; `--legs` picks
which to run (`both` by default). The `bench-core` dispatch drives native;
the bundle CI job drives web:

- **native** (`native_size` golden): `flutter build apk --release
  --analyze-size` (the per-package analysis the DevTools **Size** page
  consumes); the CLI walks the tree for the `package:hintful` node and sums
  its bytes. SDK + ABI pinned — ref `android` in the dispatch.
- **web** (`bundle_delta` golden): builds the same scene twice for web
  (with and without hintful) and diffs `main.dart.js`. SDK pinned — ref
  `any`, checked on every PR.

```bash
# native only (bench-core dispatch): ref android
dart run flutter_bench_contract:contract run --scenarios size --mode check --ref android --legs native
# web only (bundle CI job): bundle_delta is checked under its own ref `any`
dart run flutter_bench_contract:contract run --scenarios size --mode check --legs web
```

## Goldens and gate

The contract CLI (`flutter_bench_contract:contract run`) collects samples
into `build/contract_*.jsonl` and checks (`--mode check`) or records
(`--mode record`) them into `benchmarks.json`. Goldens are keyed per
reference (`any` = hardware-independent: SDK-pinned sizes; `android`,
`android-scv`, `android-tcm` = the emulator runs per library). A check with
a missing golden warns instead of failing — record once per reference, then
regressions fail the job.

Latency runs repeat and the median is recorded/checked (methodology of the
package). Every metric is "lower is better", so the check is a **one-sided
regression gate**: worse than the golden by more than the slack fails;
better always passes. Recorded goldens sit where the reference hardware was
when recorded, so the gate only answers "did it get worse?".

## Head-to-head (`compare/`) — on equal terms

The root-README numbers for the three solutions come from the same
contract run: one shared scene, the same scenario bodies, the same protocol
(profile build, warm-ups, run counts, median, slack). All of that is owned
by the package and identical for every solution. The **only** per-solution
code is the driver (`compare/bench/drivers/`) — how each library mounts the
measured content on the shared scene through its real public API. Nothing
was patched per library to make the field level; each library's API limits
show up in its numbers, or as `n/a`.

Two honest consequences, documented in the drivers and visible in the
table:

- **Content shape is each solution's price.** tutorial_coach_mark and
  hintful mount the package's real `ContractCard` (their content APIs take
  a custom widget). showcaseview's `Showcase` accepts only title +
  description, so its driver mounts the same *strings* the card carries —
  the state-specific content the S2/S3 asserts look for — not the card
  itself. Decorative-only options (showcaseview's looping "bob" animation,
  tcm's pulse) are switched off through each library's public API, as an
  app would; they are UI, outside the contract's scope, and never touch a
  timing measurement.
- **`n/a` is a fact, not a removal.** A scenario a solution cannot
  implement (S4 scroll coupling for the rival overlays, which consume
  pointer input) stays visible in the table and the footnote — it is never
  deleted.

Record the rival goldens on the same hardware as hintful's for a
consistent table:

```bash
cd benchmark/compare
dart run flutter_bench_contract:contract run --library showcaseview --store ../benchmarks.json --device <id> --mode record
dart run flutter_bench_contract:contract run --library tutorial_coach_mark --store ../benchmarks.json --device <id> --mode record
```

Column values never fall back to hintful's numbers: a rival without a
recorded golden renders `n/a` (fallback `any` is hintful-only).

## Web-drive caveat

`flutter drive` on web needs a WebDriver server and is fragile, so contract
numbers come from the Android emulator path. Web is only used for the
size-analysis builds.
