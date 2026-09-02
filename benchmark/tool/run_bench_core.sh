#!/usr/bin/env bash
# Runs the five profile benchmarks on a device/emulator plus the native-size
# analysis, then checks or records the results against benchmarks.json.
#
# Usage:
#   ./tool/run_bench_core.sh <device-id> [extra flutter drive args...]
#   BENCH_MODE=record BENCH_REF=android ./tool/run_bench_core.sh emulator-5554
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
./tool/native_size.sh >> "$report" 2>&1 \
  || echo "    (native_size failed — continuing)"

echo "==> report: $report"
dart run tool/check_goldens.dart "$report" "--$mode" --ref "$ref"