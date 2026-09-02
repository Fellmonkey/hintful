#!/usr/bin/env bash
# Native-size metric: how much hintful adds to a release Android build.
#
# Uses `flutter build apk --release --analyze-size` — the same analysis the
# DevTools "Size" page consumes. The tool prints the path of the per-package
# JSON it writes to ~/.flutter-devtools; this script greps that sentinel path
# and reads the `package:hintful` subtree from the tree (release builds
# tree-shake, so the node is exactly hintful's code that survived).
#
# One --target-platform ABI keeps the build cheap; the number is deterministic
# per SDK + ABI, so the golden lives under the 'any' reference. The script
# prints human lines plus one machine-readable sample on stdout, so redirect
# the whole output into a report file for tool/check_goldens.dart:
#
#   ./tool/native_size.sh > build/native_report.jsonl
#   dart run tool/check_goldens.dart build/native_report.jsonl --check --ref any
#
# Usage: ./tool/native_size.sh [--arch x64]
# Exit codes: 0 ok, 1 hintful node missing/unexpected, 2 build failed.
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${1:-x64}"

echo "==> building release APK with --analyze-size (android-$arch)..."
out=$(flutter build apk --release --analyze-size \
  --target-platform "android-$arch" --code-size-directory build/size 2>&1)
summary=$(echo "$out" | grep -oE "A summary of your [A-Z]+ analysis can be found at: .+\.json" || true)
if [ -z "$summary" ]; then
  echo "FAIL: could not find the code-size analysis path in build output:" >&2
  echo "$out" | tail -20 >&2
  exit 2
fi
analysis="${summary##*: }"
analysis="${analysis//$'\r'/}"
echo "==> analysis: $analysis"

# Parse the tree with a small Dart script (same JSON the DevTools Size
# page shows) — invoked via `dart run` so no python or exec bit is needed.
dart run tool/native_size_parse.dart "$analysis"
