// hintful_driver.dart — consumer #1 (hintful, the tour/tooltip/overlay
// solution). The driver is the ONLY hintful-specific code of the contract:
// it builds the neutral contract scene with hintful's own
// widgets and maps the scenario verbs (show/update/hide) onto the
// controller. Everything else — scenario procedures, collectors, goldens,
// gates — belongs to the package.
//
// The driver lives consumer-side (bench/drivers/), never in the package's
// lib/: it imports the solution under test (package:hintful), which the
// published package must never depend on.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bench_contract/flutter_bench_contract.dart';
import 'package:hintful/hintful.dart';

/// Consumer #1: hintful (tour / tooltip / overlay solution).
///
/// Content model (two states): the two ContractCard states are the
/// two steps of one tour — step 0 carries state 1, step 1 carries state 2.
/// hintful shows ONE overlay at a time and forbids reusing a target across
/// steps (tour.duplicateTargetIds assert), so step 0 anchors element B
/// (row 5) and step 1 anchors the next row (row 6); update() is a step
/// change (goTo) — hintful's genuine "content changed" flow.
class HintfulDriver implements LibraryDriver {
  HintfulDriver()
      : _controller = HintController(overlayHostBuilder: defaultOverlayHost());

  /// Engine + machine + registry. The overlay host is built lazily at the
  /// first non-idle state and disposed on hide (hintful's zero-idle
  /// mechanics — S1/S1r measure exactly this).
  final HintController _controller;

  /// Step index 0 ↔ content state 1, step index 1 ↔ content state 2.
  static const List<int> _states = [1, 2];

  /// Row anchored by step 1 (state 2). Distinct from B (row 5) — hintful
  /// does not allow the same target on two steps of one tour.
  static const int _kState2Row = 6;

  /// The state the scenario asked for last (show/update set it).
  int _expectedState = 1;

  @override
  String get name => 'hintful';

  /// hintful's tooltip rides a CompositedTransformFollower of the target's
  /// LayerLink: under scroll the compositor moves it with B — S4 coupled.
  @override
  bool get scrollCoupled => true;

  // ── Scene ───────────────────────────────────────────────────────────────

  /// The neutral scene with the tour anchors (rows 5 and 6)
  /// wrapped in [HintTarget] — hintful's registry model — only when
  /// [withLibrary] (S1 counts the tree difference against the base scene).
  @override
  Widget buildScene({required bool withLibrary, required SceneSpec spec}) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return buildContractScene(
      spec,
      withLibrary: withLibrary,
      theme: ThemeData(
        colorScheme: scheme,
        extensions: [HintTheme.minimal(scheme)],
      ),
      wrapRow: (index, row) {
        final anchored =
            withLibrary && (index == kSceneBRow || index == _kState2Row);
        if (!anchored) return row;
        return HintTarget(id: sceneRowKey(index), child: row);
      },
    );
  }

  // ── Verbs ───────────────────────────────────────────────────────────────

  @override
  Future<void> show(int state) async {
    _expectedState = state;
    if (_controller.currentState.isIdle) {
      await _controller.start(_tour());
    }
    _goToState(state);
    // TEST REGRESSION: artificial 200 ms delay to trigger S2 show_latency gate
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> update(int state) async {
    if (_controller.currentState.isIdle) {
      await show(state);
    } else {
      _expectedState = state;
      _goToState(state); // step change = hintful's content swap
    }
  }

  @override
  Future<void> hide() async => _controller.finish();

  /// True when the machine reached the step carrying [_expectedState] and no
  /// frame is scheduled (the tooltip mounts/positions on the frames the
  /// scenario pumps — the scenario owns pumping, Р7).
  @override
  bool isStable() {
    final s = _controller.currentState;
    if (s is! HintActive) return false;
    return _states[s.stepIndex] == _expectedState &&
        !SchedulerBinding.instance.hasScheduledFrame;
  }

  /// The visible ContractCard(state) — the card root carries the package's
  /// contract key, so this finder is solution-agnostic.
  @override
  Finder currentContent(int state) =>
      find.byKey(Key(contractCardKey(state)), skipOffstage: false);

  // ── Tour mapping ───────────────────────────────────────────────────────

  HintTour _tour() => HintTour(
        id: 'contract',
        steps: [
          for (final s in _states)
            HintStep(
              targetId: sceneRowKey(s == 1 ? kSceneBRow : _kState2Row),
              // Fixed side: an auto-placed tooltip re-anchors around B when
              // the free space changes under scroll — legitimate UX, but it
              // would corrupt S4's "content follows B" delta. A fixed side
              // is the honest driver choice for a contract anchored to B.
              position: TooltipPosition.bottom,
              showSkip: false,
              tooltipBuilder: (context, step, ctx) => ContractCard(state: s),
            ),
        ],
      );

  void _goToState(int state) {
    final index = _states.indexOf(state);
    if (index >= 0) _controller.goTo(index);
  }
}
