// scv_driver.dart — head-to-head consumer (bench_compare): showcaseview.
// The driver is the ONLY showcaseview-specific code of the contract: it
// builds the neutral contract scene with showcaseview's own widgets and
// maps the scenario verbs onto ShowcaseView.
//
// Content conformance (honest): showcaseview's Showcase renders ONLY
// title + description — it cannot host a custom content widget, so the
// package's ContractCard (with its contract key) cannot be mounted. The
// driver mounts the SAME strings the contract card carries (state 1 / state
// 2), so the S2/S3 presence-absence asserts still see state-specific content;
// the tooltip shape itself is showcaseview's own (documented in the
// methodology: content shape is each solution's price).
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bench_contract/flutter_bench_contract.dart';
import 'package:showcaseview/showcaseview.dart';

/// showcaseview driver: the two content states are the two Showcase targets
/// of one tour (row 5 = state 1, row 6 = state 2); update() steps the tour.
class ScvDriver implements LibraryDriver {
  ScvDriver() {
    // v5.1: Showcase widgets require a registered ShowcaseView controller
    // (the widget throws in initState without one). One registration per
    // driver instance; the singleton service is per test process anyway.
    // disableMovingAnimation: the tooltip otherwise runs a LOOPING "bob"
    // animation while shown — a frame scheduled forever, so the scenario's
    // "stable" (no scheduled frame) would never hold. Turning the loop off
    // is a driver-side rendering choice, not a timing measurement.
    ShowcaseView.register(disableMovingAnimation: true);
  }

  final GlobalKey _row5Key = GlobalKey();
  final GlobalKey _row6Key = GlobalKey();
  bool _started = false;
  int _step = 0;

  @override
  String get name => 'showcaseview';

  /// The bubble is positioned once at show time and does not re-anchor to a
  /// target moving under programmatic scroll (the overlay also consumes
  /// pointer input — legacy compare verified the page freeze) — S4 reports
  /// `unsupported`, it is not a failure.
  @override
  bool get scrollCoupled => false;

  /// The neutral contract scene with the two tour targets (rows 5 and 6)
  /// wrapped in [Showcase] — showcaseview's target model — only when
  /// [withLibrary] (S1 counts the tree difference against the base scene).
  @override
  Widget buildScene({required bool withLibrary, required SceneSpec spec}) {
    return buildContractScene(
      spec,
      withLibrary: withLibrary,
      wrapRow: (index, row) {
        if (!withLibrary) return row;
        if (index == kSceneBRow) {
          final (title, description) = kContractCardContent[1]!;
          return Showcase(
            key: _row5Key,
            title: title,
            description: description,
            child: row,
          );
        }
        if (index == _kState2Row) {
          final (title, description) = kContractCardContent[2]!;
          return Showcase(
            key: _row6Key,
            title: title,
            description: description,
            child: row,
          );
        }
        return row;
      },
    );
  }

  // ── Scenario verbs (show/update/hide) ─────────────────────────────────

  @override
  Future<void> show(int state) async {
    if (!_started) {
      ShowcaseView.get().startShowCase([_row5Key, _row6Key]);
      _started = true;
      _step = 0;
    }
    _goToStep(state);
  }

  @override
  Future<void> update(int state) async {
    if (!_started) {
      await show(state);
      return;
    }
    _goToStep(state); // step change = showcaseview's content swap
  }

  @override
  Future<void> hide() async {
    ShowcaseView.get().dismiss();
    _started = false;
    _step = 0;
  }

  /// Stable when the tour's entrance/transition animation is done (no frame
  /// scheduled). The scenario owns pumping (Р7).
  @override
  bool isStable() => !SchedulerBinding.instance.hasScheduledFrame;

  /// The state's title text inside the showcase bubble — the state-specific
  /// content the scenario asserts on (see the conformance note above).
  @override
  Finder currentContent(int state) {
    final (title, _) = kContractCardContent[state]!;
    return find.text(title);
  }

  static const int _kState2Row = 6;

  void _goToStep(int state) {
    final target = state == 2 ? 1 : 0;
    while (_step < target) {
      ShowcaseView.get().next();
      _step++;
    }
    while (_step > target) {
      ShowcaseView.get().previous();
      _step--;
    }
  }
}