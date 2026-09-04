// Guard: the shared store (benchmarks.json) must contain every published
// metric of the contract package (lib/defs.dart) — the rows the README
// table and the metrics card render from it. Runs in the VM CI job
// (`flutter test bench/`), no device needed.
//
// Background: the store was once accidentally reverted to a pre-phase-2
// state (a `git checkout` meant to strip JSON unicode-escaping noise), and
// the table/card rebuilt from that emptied store silently showed n/a in
// every S1–S6 row. This test makes that failure loud: a declared metric
// without goldens (or a library column without its ref) fails here, with a
// pointer to the record flow that restores it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bench_contract/defs.dart';
import 'package:flutter_bench_contract/goldens.dart';

/// Columns of the published README table (mirrors the manifest `readme:`
/// section): solution → its store ref. The card renders only hintful's
/// numbers; the table renders the head-to-head columns.
const Map<String, String> kLibraryRefs = {
  'hintful': 'android',
  'showcaseview': 'android-scv',
  'tutorial_coach_mark': 'android-tcm',
};

/// Resolves the store next to the package root: `flutter test bench/` runs
/// with cwd = benchmark/, but tolerate invocations from a parent directory.
String findStorePath() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final candidate = File('${dir.path}/benchmarks.json');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('benchmarks.json not found from ${Directory.current.path} '
      '— run from benchmark/ (`flutter test bench/`)');
}

void main() {
  final store = GoldenStore(path: findStorePath());
  final declared = kPublishableMetricDefs;

  test('every metric declared in the package defs has a recorded golden', () {
    for (final def in declared) {
      final value = store.load(def.key);
      expect(value, isNotNull,
          reason: '${def.key} (${def.label}) is a published contract metric '
              'but has no golden in benchmarks.json — re-run the record '
              '(`contract run --device --mode record`, size legs included).');
    }
  });

  test('published device rows resolve for every library column', () {
    // S1–S6 rows: hintful and both rivals were recorded on-device (refs
    // android / android-scv / android-tcm) — a missing ref turns the column
    // into a silent n/a, which is exactly the regression this guards.
    for (final def in kDeviceMetricDefs) {
      for (final library in kLibraryRefs.keys) {
        final ref = kLibraryRefs[library]!;
        final value = store.load(def.key, preferRefs: [ref], fallbackAny: false);
        expect(value, isNotNull,
            reason: '${def.key} (${def.label}) has no golden under ref $ref '
                '($library column) — re-run that solution\'s device record.');
      }
    }
  });

  test('size rows resolve for hintful (android / any)', () {
    // S7 rows are hintful-only (rival scenes were never shipped as size
    // targets) — the renderer reads ref android, falling back to `any`.
    for (final def in kSizeMetricDefs) {
      final value = store.load(def.key, preferRefs: const ['android', 'any']);
      expect(value, isNotNull,
          reason: '${def.key} (${def.label}) has no golden under ref android '
              'or any — re-run the size builds '
              '(`contract run --scenarios size --legs native|web`).');
    }
  });
}
