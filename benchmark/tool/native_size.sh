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

# Pick a working interpreter: on Windows, `python3` may be the Microsoft
# Store stub that prints "Python" and exits 49 without doing anything.
PYTHON_BIN=""
for cand in "${PYTHON:-}" python3 python; do
  [ -z "$cand" ] && continue
  if "$cand" --version >/dev/null 2>&1; then
    PYTHON_BIN="$cand"
    break
  fi
done
if [ -z "$PYTHON_BIN" ]; then
  echo "FAIL: no working python found (try PYTHON=/path/to/python)" >&2
  exit 2
fi
"$PYTHON_BIN" - "$analysis" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))

def find(node, name):
    if node.get('n') == name:
        return node
    for c in node.get('children') or []:
        r = find(c, name)
        if r:
            return r
    return None

def total_of(node):
    v = node.get('value')
    s = v if isinstance(v, int) else 0
    for c in node.get('children') or []:
        s += total_of(c)
    return s

pkg = find(d, 'package:hintful')
if pkg is None:
    print('FAIL: package:hintful node not found in analysis tree',
          file=sys.stderr)
    sys.exit(1)
size = total_of(pkg)
print(f'native_size: hintful contributes {size} bytes (AOT, release)')
print(f'HINTFUL_BENCH_JSON:{{"metric":"native_size","value":{size}}}')
PY
