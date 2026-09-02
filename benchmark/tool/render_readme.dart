// Renders the "Performance" section of the ROOT README: reads a bench report
// (build/bench_report.jsonl, produced by run_bench_core.sh) and replaces the
// block between `<!-- bench:start -->` and `<!-- bench:end -->` in the root
// README.md with a metrics table + the metrics-card image
// (docs/hint_metrics.png).
//
// Single-column for now (hintful only). When head-to-head comparison runs
// against showcaseview / tutorial_coach_mark land, add their names to
// [rivals] below — columns fill from the same JSONL shape and the section
// structure holds.
//
// Usage (cwd: benchmark/):
//   dart run tool/render_readme.dart build/bench_report.jsonl ../README.md
import 'dart:convert';
import 'dart:io';

import 'package:benchmark/metrics_defs.dart';

const String start = '<!-- bench:start -->';
const String end = '<!-- bench:end -->';
const String envelope = 'HINTFUL_BENCH_JSON:';

/// Comparison scaffold: empty until head-to-head runs land. Set e.g.
/// ['showcaseview', 'tutorial_coach_mark'] to re-enable the columns.
const List<String> rivals = [];

/// Compact value+unit: 170096 B -> '170 KB', 2797 -> '2797 µs'.
String fmtValue(num? value, String unit) {
  if (value == null) return '—';
  final v = value.toDouble();
  if (unit == 'B') {
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} MB';
    if (v.abs() >= 1e3) return '${(v / 1e3).round()} KB';
    return '${v.round()} B';
  }
  if (unit == 'µs') return '${v.round()} µs';
  return '${v.round()} frames';
}

Map<String, num> loadReport(File report) {
  final values = <String, num>{};
  if (!report.existsSync()) return values;
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
  return values;
}

void main(List<String> args) {
  final reportPath = args.isNotEmpty ? args[0] : 'build/bench_report.jsonl';
  final readmePath = args.length > 1 ? args[1] : '../README.md';
  final measured = loadReport(File(reportPath));

  final rows = <String>[];
  for (final (metric, label, unit) in kBenchmarkMetrics) {
    // hintful: measured value, falling back to the golden (an initial
    // render or a partial report still shows real numbers).
    var own = measured[metric];
    own ??= loadRecordedGolden(metric);
    rows.add('| $label | ${fmtValue(own, unit)} |${' — |' * rivals.length}');
  }

  final now = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)} UTC';

  final header = '| Metric | hintful |${rivals.map((r) => ' $r |').join()}';
  final divider = '|---|---|${'---|' * rivals.length}';
  final comparisonNote = rivals.isEmpty
      ? '\n\nHead-to-head runs against showcaseview / tutorial_coach_mark '
          'will add their columns here.'
      : '';
  final section = '$start\n'
      '## Performance\n\n'
      'Profile build, Android emulator, action-window averages. Methodology:\n'
      '`benchmark/README.md`.\n\n'
      '${[header, divider, ...rows].join('\n')}'
      '$comparisonNote\n\n'
      '![hintful benchmark metrics](docs/hint_metrics.png)\n\n'
      '_Recorded $stamp. Regenerate: dispatch the `bench-core` workflow '
      'with `record`._\n'
      '$end';

  final readme = File(readmePath);
  final text = readme.readAsStringSync();
  final s = text.indexOf(start);
  final e = text.indexOf(end);
  final updated = (s >= 0 && e > s)
      ? text.replaceRange(s, e + end.length, section)
      : '${text.trimRight()}\n\n$section\n';
  readme.writeAsStringSync(updated);
  stdout.writeln('rendered ${kBenchmarkMetrics.length} metrics -> $readmePath');
}