#!/usr/bin/env bash
# Runs the five profile benchmarks on a device/emulator plus the native-size
# analysis, then checks or records the results against benchmarks.json.
#
# Usage:
#   bash ./tool/run_bench_core.sh <device-id> [extra flutter drive args...]
#   BENCH_MODE=record BENCH_REF=android bash ./tool/run_bench_core.sh emulator-5554
#
# Environment:
#   BENCH_MODE   check (default) | record — record writes the measured
#                values as goldens for BENCH_REF (run once per reference)
#   BENCH_REF    golden key (default: android)
#   BENCH_REPORT report file (default: build/bench_report.jsonl)
#
# Exit code: 0 on success, 1 if regression found (check) or no samples.
set -uo pipefail
cd "$(dirname "$0")/.."

device="${1:?usage: run_bench_core.sh <device-id> [extra drive args...]}"
shift
mode="${BENCH_MODE:-check}"
ref="${BENCH_REF:-android}"
report="${BENCH_REPORT:-build/bench_report.jsonl}"

mkdir -p build
: > "$report"

# --no-dds: the in-test VM-service connection (memory benchmarks) must not
# sit behind the DDS proxy — integration_test documents the same requirement
# for its timeline API.
tests=(startup_to_show frame_step_change frame_scroll memory_idle memory_active)
for t in "${tests[@]}"; do
  echo "==> bench/${t}_test.dart on $device (profile)"
  flutter drive --no-dds --profile --driver=test_driver/integration_test.dart \
    --target="bench/${t}_test.dart" -d "$device" "$@" >> "$report" 2>&1 \
    || echo "    (drive failed for $t — continuing)"
done

echo "==> native_size (--analyze-size; no device needed)..."
# Invoked via bash: Windows commits can't carry the +x exec bit.
bash ./tool/native_size.sh >> "$report" 2>&1 \
  || echo "    (native_size failed — continuing)"

metrics_json="$(dart run tool/metrics_json.dart)"
[ -n "$metrics_json" ] || { echo "FAIL: metrics card payload is empty" >&2; exit 1; }

echo "==> metrics card (landscape golden, host render — no device)..."
# The render needs host-side engine artifacts (flutter_tester,
# material_fonts); make sure a fresh CI cache has them.
flutter precache 2>/dev/null || true

flutter test --update-goldens \
  --dart-define=HINTFUL_METRICS="$metrics_json" \
  golden/metrics_card_golden_test.dart >> "$report" 2>&1 \
  || { echo "    (metrics card golden FAILED — aborting)" >&2; exit 1; }
mkdir -p build/screenshots
cp golden/goldens/metrics_card.png build/screenshots/hint_metrics.png

echo "==> report: $report"
dart run tool/check_goldens.dart "$report" "--$mode" --ref "$ref"