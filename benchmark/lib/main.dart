import 'package:flutter/material.dart';

import 'package:hintful/hintful.dart';

import 'benchmark_harness.dart';

/// Web entry for the bundle-delta build: [BenchmarkApp] with the engine.
/// `tool/bundle_delta.sh` diffs this target's `main.dart.js` against
/// [main_baseline] — the difference is hintful's startup-bundle cost.
void main() {
  runApp(
    BenchmarkApp(
      controller: HintController(overlayHostBuilder: defaultOverlayHost()),
      tour: benchmarkTour(),
    ),
  );
}
