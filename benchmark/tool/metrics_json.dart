// Merges the bench report into a base64 JSON payload for the metrics card
// (golden/metrics_card_golden_test.dart): measured values from the report,
// baselines from the recorded goldens, so the card can show green/red deltas
// against the mark. Keys missing from the report (e.g. bundle_delta,
// measured by the separate bundle CI job) fall back to the goldens, so the
// card always renders every metric. Output is base64 — it travels through
// shell quoting and the Flutter toolchain as a plain dart-define value,
// where raw JSON would break on its quotes.
//
// Usage (cwd: benchmark/): dart run tool/metrics_json.dart
import 'dart:convert';
import 'dart:io';

import 'package:benchmark/metrics_defs.dart';

const String envelope = 'HINTFUL_BENCH_JSON:';

void main() {
  final values = <String, num>{};
  final report = File('build/bench_report.jsonl');
  if (report.existsSync()) {
    for (final line in report.readAsLinesSync()) {
      final i = line.indexOf(envelope);
      if (i < 0) continue;
      try {
        final sample = jsonDecode(line.substring(i + envelope.length).trim())
            as Map<String, dynamic>;
        final value = sample['value'];
        if (value is num) values[sample['metric'] as String] = value;
      } on FormatException {
        // log noise between samples
      }
    }
  }

  final baseline = <String, num>{};
  for (final (key, _, _) in kBenchmarkMetrics) {
    final golden = loadRecordedGolden(key);
    if (golden != null) {
      baseline[key] = golden;
      values.putIfAbsent(key, () => golden);
    }
  }

  final payload = <String, Object?>{
    'values': values,
    'baseline': baseline,
    // All seven metrics are "lower is better" (latencies, heap, sizes).
    'lower_is_better': {for (final key in values.keys) key: true},
  };
  final json = jsonEncode(payload);
  stdout.write(base64Encode(utf8.encode(json)));
}