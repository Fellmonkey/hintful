// tcm_driver.dart — head-to-head consumer (bench_compare):
// tutorial_coach_mark. The two content states are the two TargetFocus steps
// of one tour (row 5 = state 1, row 6 = state 2); update() is next()/
// previous(). TargetContent.builder CAN host a custom widget, so the real
// ContractCard (with its contract key) is mounted — full content
// conformance.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bench_contract/flutter_bench_contract.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// tutorial_coach_mark driver.
class TcmDriver implements LibraryDriver {
  final GlobalKey _row5Key = GlobalKey();
  final GlobalKey _row6Key = GlobalKey();
  TutorialCoachMark? _controller;

  /// Captured by the scene host widget (a live context under MaterialApp,
  /// above the Scaffold) — tcm's show() needs a context at call time and the
  /// driver has no tester access (Р7: the scenario owns pumping).
  BuildContext? _context;

  /// Last requested content state (show/update set it).
  int _expectedState = 1;

  /// Current tour step (0 = state 1, 1 = state 2).
  int _step = 0;

  @override
  String get name => 'tutorial_coach_mark';

  /// The focus light is captured at show time and does not re-anchor to a
  /// target moving under programmatic scroll (the overlay is full-screen and
  /// consumes input — legacy compare verified the page freeze) — S4 reports
  /// `unsupported`, it is not a failure.
  @override
  bool get scrollCoupled => false;

  /// The neutral contract scene with the two tour targets (rows 5 and 6)
  /// carrying GlobalKeys only — tcm spotlights keyed widgets, no wrapper
  /// subtree is added (S1 measures this: idle diff ≈ 0 for tcm). The
  /// context capturer exists only in the with-library scene — the base
  /// scene (S1) must not touch the solution at all.
  @override
  Widget buildScene({required bool withLibrary, required SceneSpec spec}) {
    return buildContractScene(
      spec,
      withLibrary: withLibrary,
      wrapRow: (index, row) {
        if (!withLibrary) return row;
        if (index == kSceneBRow) {
          return KeyedSubtree(key: _row5Key, child: row);
        }
        if (index == _kState2Row) {
          return KeyedSubtree(key: _row6Key, child: row);
        }
        return row;
      },
      wrapHome: withLibrary ? (home) => _ContextCapture(driver: this, child: home) : null,
    );
  }

  // ── Scenario verbs (show/update/hide) ─────────────────────────────────

  @override
  Future<void> show(int state) async {
    final ctx = _context;
    if (ctx == null) {
      throw StateError('TcmDriver.show() before the scene mounted');
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.isShowing) {
      // One controller per show cycle: after finish() a fresh tour is needed
      // (warm-ups in S5/S6 show→hide repeatedly).
      _controller = TutorialCoachMark(
        targets: [
          _target(_row5Key, 1),
          _target(_row6Key, 2),
        ],
        textSkip: 'Skip',
        // pulseEnable: the target pulse otherwise runs a LOOPING animation
        // while the step is shown — a frame scheduled forever, so the
        // scenario's "stable" (no scheduled frame) would never hold.
        pulseEnable: false,
      )..show(context: ctx);
      _step = 0;
    }
    _expectedState = state;
    _goToStep(state);
  }

  @override
  Future<void> update(int state) async {
    if (_controller == null || !_controller!.isShowing) {
      await show(state);
      return;
    }
    _expectedState = state;
    _goToStep(state); // step change = tcm's content swap
  }

  @override
  Future<void> hide() async {
    _controller?.finish();
    _controller = null;
  }

  /// True when the tour is on the step carrying [_expectedState] and no frame
  /// is scheduled (tcm animates focus + tooltip on transitions — stability
  /// means the animation ran out; the scenario owns pumping).
  @override
  bool isStable() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.isShowing) return false;
    final expectedStep = _expectedState == 2 ? 1 : 0;
    return _step == expectedStep &&
        !SchedulerBinding.instance.hasScheduledFrame;
  }

  /// The visible ContractCard(state) — tcm mounts the real card via the
  /// TargetContent builder, so the contract key works (full conformance).
  @override
  Finder currentContent(int state) =>
      find.byKey(Key(contractCardKey(state)), skipOffstage: false);

  static const int _kState2Row = 6;

  TargetFocus _target(GlobalKey key, int state) => TargetFocus(
        keyTarget: key,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => ContractCard(state: state),
          ),
        ],
      );

  void _goToStep(int state) {
    final target = state == 2 ? 1 : 0;
    final ctrl = _controller!;
    while (_step < target) {
      ctrl.next();
      _step++;
    }
    while (_step > target) {
      ctrl.previous();
      _step--;
    }
  }
}

/// Exposes a live context (under MaterialApp, above the Scaffold) to the
/// driver — tcm's show(context:) needs one, and the driver cannot capture it
/// from buildScene (which only returns the widget tree).
class _ContextCapture extends StatefulWidget {
  const _ContextCapture({required this.driver, required this.child});

  final TcmDriver driver;
  final Widget child;

  @override
  State<_ContextCapture> createState() => _ContextCaptureState();
}

class _ContextCaptureState extends State<_ContextCapture> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.driver._context = context;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}