// The benchmark metrics shared by every consumer (metrics card, README
// renderer): (metric key, display label, unit of the raw value). The order
// drives the card layout and the README table — keep it stable.
import 'dart:convert';
import 'dart:io';

const List<(String, String, String)> kBenchmarkMetrics = [
  ('startup_to_show', 'Startup to first tooltip', 'frames'),
  ('frame_step_change', 'Step transition (avg build)', 'µs'),
  ('frame_scroll', 'Scroll frame (avg build)', 'µs'),
  ('memory_idle', 'Heap drift after finish', 'B'),
  ('memory_active', 'Active step heap delta', 'B'),
  ('native_size', 'Native AOT size', 'B'),
  ('bundle_delta', 'Web startup bundle delta', 'B'),
];

/// Recorded golden for [metric] from `benchmarks.json`, preferring the
/// canonical references `android`, then `any`, then the first recorded
/// value. Null when the file is missing, corrupt, or has no entry.
num? loadRecordedGolden(String metric, {String path = 'benchmarks.json'}) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final metricsDoc = (doc['metrics'] as Map?)?.cast<String, dynamic>();
    final byRef = ((metricsDoc?[metric] as Map?)?['goldens'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    for (final ref in const ['android', 'any']) {
      final value = byRef[ref];
      if (value is num) return value;
    }
    return byRef.values.whereType<num>().firstOrNull;
  } on FormatException {
    return null;
  }
}