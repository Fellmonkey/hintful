# hintful benchmarks

The benchmark suite measures the engine's performance contracts — zero idle
cost, cheap step transitions, cheap scrolling under a tour, fast startup —
and its size footprint. Reference values live in `benchmarks.json` and are
enforced by CI; the same files run locally as fast VM sanity checks.

## Layout

The benchmark is its own package at the repo root (sibling of `example/`),
because its harness ([`BenchmarkApp`](lib/benchmark_harness.dart))
deliberately does not use the example app — the example's bootstrap would
leak into the numbers and needs plugins that VM runs don't have. In short:

- `bench/*_test.dart` — the five device benchmarks (run via `flutter drive`);
- `lib/benchmark_harness.dart` — the shared scene and tour;
- `lib/main.dart` / `lib/main_baseline.dart` — web entry points with/without
  hintful, for the bundle-delta build;
- `tool/` — runner, golden checks, size-analysis scripts.

## Metrics

| File | Measures | Contract |
|---|---|---|
| `bench/startup_to_show_test.dart` | `start()` → first tooltip frame | ≤ 3 frames |
| `bench/frame_step_change_test.dart` | build/raster cost of next/previous | avg build ≪ 16.6 ms |
| `bench/frame_scroll_test.dart` | frame cost of scrolling under a tour | avg build ≪ 16.6 ms |
| `bench/memory_idle_test.dart` | heap at idle + after finish | drift ≈ 0 after finish (full release) |
| `bench/memory_active_test.dart` | heap delta of an active step | thin overlay |
| `tool/native_size.sh` | hintful's native AOT contribution | golden `any` |
| `tool/bundle_delta.sh` | hintful's web startup-bundle contribution | golden `any` |

Reference values (Flutter 3.47.0, android-x64 emulator): 2 frames to the
first tooltip, ~2.8 ms build per step transition, ~5.1 ms build per scroll
frame, ~170 KB live overlay heap, ~42 KB heap drift after finish, 69 KB
native AOT, 53.7 KB web startup bundle. Recorded values live in
`benchmarks.json` and are compared by the `bench-core` and `bundle` CI jobs.

## Running

Sanity (fast, CI-friendly, no device):

```bash
cd benchmark
flutter test bench/
```

The memory heap numbers need a VM service, which `flutter test` runs don't
expose — there they print "heap unavailable" and only the structural
invariants are asserted. The files live in `bench/`, not
`integration_test/`, because that directory forces a device; `flutter drive
--target` accepts any path.

Contract (profile build, real device/emulator):

```bash
flutter drive --no-dds --profile \
  --driver=test_driver/integration_test.dart \
  --target=bench/startup_to_show_test.dart \
  -d <device>
```

`--no-dds` is required: the in-test VM-service connection (memory
benchmarks) must not sit behind the DDS proxy — the same requirement
`integration_test` documents for its timeline API. Each benchmark alternates
its action several times (6 next/previous cycles, 10 drags, …), so reported
values are averages, never a single best frame.

## Size

- `tool/native_size.sh` — runs `flutter build apk --release --analyze-size`
  (the same per-package analysis the DevTools **Size** page consumes) and
  reads the `package:hintful` subtree — hintful's tree-shaken code.
  Deterministic per SDK + ABI (golden `any`).
- `tool/bundle_delta.sh` — builds the same scene twice for web (with and
  without hintful) and diffs `main.dart.js`.

```bash
./tool/native_size.sh > build/native_report.jsonl
./tool/bundle_delta.sh > build/bundle_report.jsonl
```

## Goldens

Each benchmark emits one machine-readable line per sample
(`HINTFUL_BENCH_JSON:{...}`). `tool/check_goldens.dart` records samples as
goldens (`--record`) or checks a run against them (`--check`). Goldens are
keyed per reference setup (`any` = hardware-independent: structural frame
counts, SDK-pinned sizes; `android` = the emulator contract), so different
hardware doesn't cross-compare. A `--check` with a missing golden warns
instead of failing — record once per reference, then regressions fail the
job.

```bash
dart run tool/check_goldens.dart build/bench_report.jsonl --check --ref android
dart run tool/check_goldens.dart build/bench_report.jsonl --record --ref android
```

## Whole contract on a device

```bash
cd benchmark
./tool/run_bench_core.sh emulator-5554           # check against goldens
BENCH_MODE=record ./tool/run_bench_core.sh emulator-5554  # record goldens
```

Runs the five benchmarks via `flutter drive --no-dds --profile`, then the
native-size analysis, collects the report and checks/records it. The same
script powers CI's `bench-core` job: it checks on main pushes, and records
goldens when the workflow is dispatched manually with its `record` input.

## Web-drive caveat

`flutter drive` on web needs a WebDriver server and is fragile (on
Flutter 3.47 + this setup it hangs right after the web build), so contract
numbers come from the Android emulator path. Web is only used for the
size-analysis builds.