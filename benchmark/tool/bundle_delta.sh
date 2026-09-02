#!/usr/bin/env bash
# Startup-bundle delta: how much hintful adds to the web startup bundle.
#
# Builds two web variants of the same benchmark scene and diffs `main.dart.js`:
#   lib/main.dart          — the engine (BenchmarkApp + hintful)
#   lib/main_baseline.dart — the same scene without hintful
# delta = engine − baseline = hintful's contribution.
#
# Prints a machine-readable sample for tool/check_goldens.dart (golden
# `any` in benchmarks.json, checked by the bundle CI job). A deferred
# engine would make the target 0 bytes — re-key the golden then.
#
# Exit codes: 0 = ok, 1 = delta over ceiling, 2 = build failed.
set -euo pipefail
cd "$(dirname "$0")/.."

max_bytes="${1:-1048576}"

echo "==> building baseline (no hintful)..."
if ! flutter build web --target=lib/main_baseline.dart \
  -o build/bundle_baseline >/dev/null 2>build/bundle_baseline.err; then
  echo "FAIL: baseline build failed:" >&2
  cat build/bundle_baseline.err >&2
  exit 2
fi

echo "==> building with engine..."
if ! flutter build web --target=lib/main.dart \
  -o build/bundle_engine >/dev/null 2>build/bundle_engine.err; then
  echo "FAIL: engine build failed:" >&2
  cat build/bundle_engine.err >&2
  exit 2
fi

baseline=$(wc -c < build/bundle_baseline/main.dart.js)
engine=$(wc -c < build/bundle_engine/main.dart.js)
delta=$((engine - baseline))

echo "main.dart.js sizes:"
echo "  baseline (no hintful): $baseline bytes"
echo "  with engine:           $engine bytes"
echo "  hintful contribution:  $delta bytes"

if [ "$delta" -lt 0 ]; then
  echo "FAIL: negative delta ($delta) — the baseline build must not exceed the engine build" >&2
  exit 1
fi

if [ "$delta" -gt "$max_bytes" ]; then
  echo "FAIL: delta $delta bytes > ceiling $max_bytes bytes" >&2
  exit 1
fi
echo "OK: delta $delta bytes within ceiling $max_bytes bytes"
# Machine-readable sample for tool/check_goldens.dart (golden lives under
# the 'any' reference in benchmarks.json): the golden is checked in CI by
# the bundle job; this line makes the script's output a valid report.
echo "HINTFUL_BENCH_JSON:{\"metric\":\"bundle_delta\",\"value\":$delta}"