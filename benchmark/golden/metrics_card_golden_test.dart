import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:benchmark/metrics_defs.dart';

/// Renders the benchmark metrics card as a LANDSCAPE golden (2400x1080,
/// real Roboto from the Flutter SDK's material fonts — no device, no
/// screenshots, fully deterministic). The image is published to
/// docs/hint_metrics.png by the bench-core workflow.
///
/// Data comes from the `HINTFUL_METRICS` dart-define (base64 JSON produced
/// by tool/metrics_json.dart): measured values + recorded goldens as a
/// baseline, so each row shows a green/red delta chip ("improved −n% /
/// regressed +n%") and marketing subtitles (ms + FPS-class for timings).
///
/// Run (from benchmark/):
///   flutter test --update-goldens \
///     --dart-define=HINTFUL_METRICS="$(dart run tool/metrics_json.dart)" \
///     golden/metrics_card_golden_test.dart
///
/// Without the define the test skips, so plain `flutter test` stays green.
void main() {
  testWidgets('metrics card golden (landscape)', (tester) async {
    final raw = const String.fromEnvironment('HINTFUL_METRICS');
    if (raw.isEmpty) {
      markTestSkipped('no HINTFUL_METRICS define — nothing to render');
      return;
    }

    await _loadFonts();

    // Landscape output: 2400x1080 at dpr 1.0 → golden is exactly that size.
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, dynamic> values = const {};
    Map<String, dynamic> baseline = const {};
    try {
      final payload =
          (jsonDecode(utf8.decode(base64Decode(raw))) as Map).cast<String, dynamic>();
      values =
          (payload['values'] as Map?)?.cast<String, dynamic>() ?? const {};
      baseline =
          (payload['baseline'] as Map?)?.cast<String, dynamic>() ?? const {};
    } catch (_) {
      values = const {};
    }
    // ignore: avoid_print
    print('HINTFUL_METRICS: values=${values.length} baseline=${baseline.length}');

    await tester.pumpWidget(MetricsCard(values: values, baseline: baseline));
    await tester.pump(const Duration(milliseconds: 300));

    // Every metric with a value must be rendered on screen — an empty data
    // path fails here instead of publishing a blank card.
    for (final (key, _, unit) in kBenchmarkMetrics) {
      final v = values[key];
      if (v != null) {
        final text = MetricsCard.formatValue(v.toDouble(), unit);
        final rect = tester.getRect(find.text(text));
        expect(rect.width, greaterThan(0), reason: '$key ($text) visible');
        expect(rect.left >= 0 && rect.top >= 0, isTrue,
            reason: '$key ($text) not clipped');
      }
    }

    await expectLater(
      find.byType(MetricsCard),
      matchesGoldenFile('goldens/metrics_card.png'),
    );
  });
}

class MetricsCard extends StatelessWidget {
  const MetricsCard({super.key, required this.values, required this.baseline});

  /// metric key -> measured value (bytes for the size metrics).
  final Map<String, dynamic> values;

  /// metric key -> recorded golden (the mark the deltas compare against).
  final Map<String, dynamic> baseline;

  /// Display value: bytes as KB/MB, latencies as ms, frames as-is.
  static String formatValue(double v, String unit) {
    if (v <= 0) return '—';
    switch (unit) {
      case 'B':
        if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} MB';
        if (v >= 1e3) return '${(v / 1e3).round()} KB';
        return '${v.round()} B';
      case 'µs':
        final ms = v / 1000;
        if (ms >= 100) return '${ms.round()} ms';
        return '${ms.toStringAsFixed(1)} ms';
      default:
        return '${v.round()} frames';
    }
  }

  /// Green (improved) / red (regressed) percent chip vs the baseline.
  /// All seven metrics are "lower is better".
  static _Delta? _deltaOf(double v, double? base) {
    if (base == null || base <= 0 || v <= 0) return null;
    final d = (v - base) / base;
    if (d.abs() < 0.005) return const _Delta(text: '≈', color: _kNeutral);
    final improved = d < 0;
    return _Delta(
      text: '${improved ? '−' : '+'}${(d.abs() * 100).round()}%',
      color: improved ? _kGreen : _kRed,
    );
  }

  /// Marketing subtitle per metric.
  static String subtitleOf(String key, double v, String unit) {
    if (v <= 0) return '';
    switch (unit) {
      case 'µs':
        final ms = v / 1000;
        final fps = (1000 / ms).round();
        final budgetPct = (ms / 16.667 * 100).round();
        return '$ms ms · ≈$fps FPS-class · $budgetPct% of the 16.6 ms budget';
      case 'frames':
        return 'first tooltip in $v frames — no re-layout while scrolling';
      default:
        return switch (key) {
          'memory_idle' => 'engine absent from the tree when idle',
          'memory_active' => 'entire overlay: scrim + tooltip + follower',
          'native_size' => 'tree-shaken; deferred-module target: 0',
          'bundle_delta' => 'loads lazily with the rest of the app',
          _ => '',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _kTeal),
        fontFamily: 'Roboto',
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFEDF1F4),
        body: Center(
          child: Container(
            width: 2260,
            height: 990,
            margin: const EdgeInsets.symmetric(horizontal: 70, vertical: 45),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 36,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 26),
                Expanded(
                  child: _TilesGrid(
                    rows: kBenchmarkMetrics,
                    values: values,
                    baseline: baseline,
                  ),
                ),
                const SizedBox(height: 18),
                const _Legend(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF26A69A)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'hintful benchmarks',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'RobotoBold',
                    fontSize: 42,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'profile build · Android x64 · action-window averages',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 21,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              'lower is better',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontFamily: 'RobotoMedium',
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TilesGrid extends StatelessWidget {
  const _TilesGrid({
    required this.rows,
    required this.values,
    required this.baseline,
  });

  final List<(String, String, String)> rows;
  final Map<String, dynamic> values;
  final Map<String, dynamic> baseline;

  @override
  Widget build(BuildContext context) {
    // 7 metrics → two columns: 4 + 3 (the last slot on the right carries a
    // methodology note).
    final left = rows.take(4).toList();
    final right = rows.skip(4).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (key, label, unit) in left)
                _MetricTile(
                  metricKey: key,
                  label: label,
                  unit: unit,
                  value: (values[key] as num?)?.toDouble() ?? 0,
                  base: (baseline[key] as num?)?.toDouble(),
                ),
            ],
          ),
        ),
        const SizedBox(width: 36),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (key, label, unit) in right)
                _MetricTile(
                  metricKey: key,
                  label: label,
                  unit: unit,
                  value: (values[key] as num?)?.toDouble() ?? 0,
                  base: (baseline[key] as num?)?.toDouble(),
                ),
              const _MethodNote(),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.metricKey,
    required this.label,
    required this.unit,
    required this.value,
    required this.base,
  });

  final String metricKey;
  final String label;
  final String unit;
  final double value;
  final double? base;

  @override
  Widget build(BuildContext context) {
    final delta = MetricsCard._deltaOf(value, base);
    final subtitle = MetricsCard.subtitleOf(metricKey, value, unit);
    final fraction = _fraction();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF37474F),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      MetricsCard.formatValue(value, unit),
                      style: const TextStyle(
                        fontSize: 30,
                        fontFamily: 'RobotoBold',
                        color: Color(0xFF00695C),
                      ),
                    ),
                    if (delta != null)
                      Text(
                        delta.text,
                        style: TextStyle(
                          fontSize: 19,
                          fontFamily: 'RobotoMedium',
                          color: delta.color,
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 24,
              color: const Color(0xFFE0E7EA),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00897B), Color(0xFF4DB6AC)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF78909C),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _fraction() {
    if (value <= 0) return 0;
    final exp = (math.log(value) / math.ln10).ceil();
    final cap = math.pow(10, exp).toDouble();
    final nice = cap / 2 >= value ? cap / 2 : (cap / 5 >= value ? cap / 5 : cap);
    return (value / nice).clamp(0.1, 1.0);
  }
}

class _MethodNote extends StatelessWidget {
  const _MethodNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 8),
      child: Text(
        'Methodology: benchmark/README.md.\nRegenerate: bench-core workflow, record input.',
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 15, color: Color(0xFF78909C)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '● improved vs mark',
          style: TextStyle(
            fontSize: 17,
            fontFamily: 'RobotoMedium',
            color: _kGreen,
          ),
        ),
        SizedBox(width: 24),
        Text(
          '● regressed vs mark',
          style: TextStyle(
            fontSize: 17,
            fontFamily: 'RobotoMedium',
            color: _kRed,
          ),
        ),
      ],
    );
  }
}

class _Delta {
  const _Delta({required this.text, required this.color});

  final String text;
  final Color color;
}

Future<void> _loadFonts() async {
  // Roboto lives in every Flutter SDK (bin/cache/artifacts/material_fonts),
  // so the golden renders with real glyphs but nothing is vendored into the
  // repo; FLUTTER_ROOT is set by the flutter tool for test processes.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    throw StateError('FLUTTER_ROOT is not set — cannot load SDK fonts for '
        'the metrics-card golden render');
  }
  final dir = '$root${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts'
      '${Platform.pathSeparator}material_fonts';
  Future<ByteData> read(String file) async =>
      ByteData.view(File('$dir${Platform.pathSeparator}$file')
          .readAsBytesSync().buffer);
  await Future.wait<void>([
    (FontLoader('Roboto')..addFont(read('roboto-regular.ttf'))).load(),
    (FontLoader('RobotoMedium')..addFont(read('roboto-medium.ttf'))).load(),
    (FontLoader('RobotoBold')..addFont(read('roboto-bold.ttf'))).load(),
  ]);
}

const _kTeal = Color(0xFF00695C);
const _kGreen = Color(0xFF2E7D32);
const _kRed = Color(0xFFC62828);
const _kNeutral = Color(0xFF78909C);