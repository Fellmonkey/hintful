import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart';

/// Shared measurement utilities for the benchmark suite.
///
/// Deliberately free of `flutter_test` so the same helpers can later be
/// reused by reporting harnesses. Timings are in microseconds.

/// One frame's budget at 60 Hz, in microseconds.
const int kFrameBudgetUs = 16666; // 16.6 ms

/// A window of [FrameTiming]s collected while a benchmark action ran.
class FrameWindow {
  FrameWindow(this.timings);

  final List<FrameTiming> timings;
  double get _sumBuildUs => timings
      .fold<int>(0, (sum, t) => sum + t.buildDuration.inMicroseconds)
      .toDouble();

  double get _sumRasterUs => timings
      .fold<int>(0, (sum, t) => sum + t.rasterDuration.inMicroseconds)
      .toDouble();

  /// Average build phase per frame, µs.
  double get avgBuildUs => timings.isEmpty ? 0 : _sumBuildUs / timings.length;

  /// Average raster phase per frame, µs.
  double get avgRasterUs => timings.isEmpty ? 0 : _sumRasterUs / timings.length;

  /// Frames whose build+raster exceeded the 60 Hz budget.
  int get slowFrames => timings
      .where((t) =>
          t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds >
          kFrameBudgetUs)
      .length;

  @override
  String toString() => '${timings.length} frames · build avg '
      '${avgBuildUs.toStringAsFixed(0)} µs · raster avg '
      '${avgRasterUs.toStringAsFixed(0)} µs · slow >16.6 ms: $slowFrames';
}

/// Collects [FrameTiming]s while [action] runs and returns the window.
Future<FrameWindow> collectFrames(Future<void> Function() action) async {
  final timings = <FrameTiming>[];
  // The callback receives a batch per frame — append, not replace.
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(onTimings);
  try {
    await action();
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
  }
  return FrameWindow(timings);
}

/// Best-effort handle to the heap of the running test isolate.
///
/// Connects like `integration_test`'s timeline API: the address is built
/// from `developer.Service.getInfo()` as `ws://localhost:port/path/ws`. This
/// requires the run NOT to sit behind the DDS proxy — with `flutter drive`,
/// pass `--no-dds`. In plain `flutter test` VM runs `serverUri == null`, so
/// [VmServiceHeap.connect] returns `null` and callers degrade gracefully.
class VmServiceHeap {
  VmServiceHeap._(this._service, this._isolateId);

  final vm_service.VmService _service;
  final String _isolateId;

  /// Connects to the VM service of the running isolate, or `null`.
  static Future<VmServiceHeap?> connect() async {
    try {
      final info = await developer.Service.getInfo();
      final uri = info.serverUri;
      if (uri == null) return null;
      // Same shape integration_test uses in `enableTimeline()`:
      //   ws://localhost:<port><path>ws
      final address = 'ws://localhost:${uri.port}${uri.path}ws';
      final service = await vmServiceConnectUri(address);
      final vm = await service.getVM();
      final isolate = vm.isolates?.firstWhere(
        (iso) => iso.isSystemIsolate != true,
      );
      if (isolate?.id == null) return null;
      return VmServiceHeap._(service, isolate!.id!);
    } catch (_) {
      return null;
    }
  }

  /// Used heap bytes of the test isolate after a forced GC, or `null`.
  Future<int?> usedBytes() async {
    try {
      final profile = await _service.getAllocationProfile(
        _isolateId,
        gc: true,
      );
      return profile.memoryUsage?.heapUsage;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async => _service.dispose();
}

/// Emits one machine-readable benchmark sample on stdout.
///
/// Format: `HINTFUL_BENCH_JSON:<json>` — greppable, stable envelope around
/// the human log lines. [tool/check_goldens.dart] reads these lines from a
/// report file: every sample carries `metric` and a nullable `value`
/// (null = could not measure — the collector skips such samples).
void reportMetric(String metric, num? value, {Map<String, Object>? extra}) {
  final payload = <String, Object?>{
    'metric': metric,
    'value': value,
    if (extra != null) ...extra,
  };
  // ignore: avoid_print
  print('HINTFUL_BENCH_JSON:${jsonEncode(payload)}');
}
