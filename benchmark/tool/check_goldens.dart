// The golden manager for the benchmark contract.
//
// Reads machine-readable samples (`HINTFUL_BENCH_JSON:` lines) from a run
// report and either records them into `benchmarks.json` as goldens
// (`--record`) or checks the current run against existing goldens
// (`--check`, the CI default). Goldens are keyed per reference ("android",
// "web",...) so runs on different hardware/setups don't cross-compare.
//
// Usage:
//   dart run tool/check_goldens.dart <report.jsonl> --check --ref android
//   dart run tool/check_goldens.dart <report.jsonl> --record --ref android
//   [--slack 0.3]  relative tolerance per metric (default 0.3)
//
// Exit codes: 0 ok, 1 regressions found (--check) or I/O error.
//
// A sample line looks like: HINTFUL_BENCH_JSON:{"metric":"startup_to_show","value":2}
// Missing goldens (a `--check` run before any `--record`) print a warning and
// do not fail — the first benchmark recording on a reference establishes them.

import 'dart:convert';
import 'dart:io';

const String envelope = 'HINTFUL_BENCH_JSON:';
const String goldensPath = 'benchmarks.json';

void usage() {
  stderr.writeln('''
usage: dart run tool/check_goldens.dart <report.jsonl> --check|--record \\
            --ref <reference> [--slack 0.3]

  --check   compare samples from the report against goldens; fail on
            regression (missing golden = warning only)
  --record  write the report's samples as goldens for <reference>
  --ref     golden key under which values are stored (e.g. android, web)
  --slack   relative tolerance, 0..1 (default 0.3)''');
}

double slack = 0.3;
bool record = false;
String ref = '';
String? reportPath;

void parseArgs(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        record = false;
      case '--record':
        record = true;
      case '--ref':
        ref = args[++i];
      case '--slack':
        slack = double.parse(args[++i]);
      default:
        if (args[i].endsWith('.jsonl')) reportPath = args[i];
    }
  }
  if (reportPath == null || ref.isEmpty) {
    usage();
    exit(2);
  }
}

/// Parses [line] into a (metric, value) sample, or null.
///
/// The envelope is searched anywhere in the line, not only at its start:
/// under `flutter drive` the app's stdout is prefixed by the tool
/// (`I/flutter ( <pid>): ...`), while plain `flutter test` prints raw.
Map<String, Object?>? parseSample(String line) {
  final start = line.indexOf(envelope);
  if (start < 0) return null;
  final payload = line.substring(start + envelope.length).trim();
  final decoded = jsonDecode(payload) as Map<String, dynamic>;
  return decoded.cast<String, Object?>();
}

void main(List<String> args) {
  parseArgs(args);

  final file = File(goldensPath);
  final dynamic doc = file.existsSync()
      ? jsonDecode(file.readAsStringSync())
      : <String, Object?>{'metrics': <String, Object?>{}};
  final metrics =
      (doc['metrics'] as Map<String, dynamic>).cast<String, Object?>();

  // Collect samples from the report.
  final samples = <String, num?>{};
  for (final line in File(reportPath!).readAsLinesSync()) {
    final sample = parseSample(line);
    if (sample == null) continue;
    final metric = sample['metric'] as String?;
    final value = sample['value'];
    if (metric == null || value == null) continue;
    samples[metric] = (value as num);
  }
  if (samples.isEmpty) {
    stderr.writeln('No HINTFUL_BENCH_JSON samples found in $reportPath');
    exit(1);
  }

  final measured = samples.keys.toList()..sort();
  stdout.writeln('samples: ${measured.join(', ')} (ref=$ref, '
      '${record ? 'record' : 'check'})');

  if (record) {
    var changed = false;
    for (final metric in measured) {
      final golden = samples[metric];
      if (golden == null) continue;
      final metricDoc = metrics.putIfAbsent(
        metric,
        () => <String, Object?>{'unit': metric, 'goldens': <String, Object?>{}},
      ) as Map<String, dynamic>;
      final goldens = metricDoc.putIfAbsent(
          'goldens', () => <String, Object?>{}) as Map<String, dynamic>;
      goldens[ref] = golden;
      stdout.writeln('recorded $metric = $golden (ref=$ref)');
      changed = true;
    }
    if (changed) {
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc));
      stdout.writeln('wrote $goldensPath');
    }
    return;
  }

  // Check mode.
  var failures = 0;
  for (final metric in measured) {
    final value = samples[metric]!;
    final metricDoc = metrics[metric] as Map<String, dynamic>?;
    final goldens = metricDoc?['goldens'] as Map<String, dynamic>? ?? const {};
    final golden = goldens[ref] ?? goldens['any'];
    if (golden == null) {
      stdout.writeln('  $metric: no golden under ref "$ref" — run '
          '"--record" once on the reference to establish it');
      continue;
    }
    final g = golden as num;
    final drift = (value - g).abs();
    final limit = (g * slack).abs().ceil().clamp(1, 1 << 62);
    if (drift > limit) {
      stderr.writeln('  FAIL $metric: measured $value, golden $g (±$limit)');
      failures++;
    } else {
      stdout.writeln('  $metric: $value within $g (±$limit)');
    }
  }
  if (failures > 0) {
    stderr
        .writeln('REGRESSION: $failures metric(s) outside the golden envelope');
    exit(1);
  }
  stdout.writeln('OK: all measured metrics within their goldens');
}
