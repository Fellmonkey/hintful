import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hintful_example/main.dart';

/// Smoke tests of the demo app: start a tour, walk all 4 steps (including
/// the waiting phase of the deferred target), remove the overlay, showHint,
/// light/dark, versioned intro.
void main() {
  setUp(() {
    // The versioned-intro demo stores shown-state on shared_preferences.
    SharedPreferences.setMockInitialValues({});
  });

  /// Pump the app + one extra frame for the async store init (prefs load
  /// resolves → setState → the demo card shows the real status). The demo
  /// list fits a phone screen (800×900) — the default 800×600 test surface
  /// would leave the lower targets (stats card, first workout row) outside
  /// the ListView's lazy build range.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump();
  }

  /// A demo button lives below the app content: the default finders only see
  /// painted children, so `skipOffstage: false` lets `ensureVisible` scroll it
  /// in from either direction (the wide cache band keeps it mounted).
  Future<void> tapDemoButton(WidgetTester tester, String label) async {
    final button = find.text(label, skipOffstage: false);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
  }

  /// Start a tour from a demo button: the tour's targets sit above the demo
  /// card, so the engine's 350 ms auto-scroll (started on the frame after the
  /// step activates) gets two real beats before the assertions.
  Future<void> startTour(WidgetTester tester, String label) async {
    await tapDemoButton(tester, label);
    await tester.pump(); // frame 1: scrim (position snapshot post-frame)
    await tester.pump(const Duration(milliseconds: 400)); // autoScroll starts
    await tester.pump(const Duration(milliseconds: 400)); // autoScroll lands
    await tester.pump(); // step tooltip at the right place
  }

  /// Advance one step with the same allowance for auto-scroll.
  Future<void> nextStep(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pump(); // frame 1: scrim (position snapshot post-frame)
    await tester.pump(const Duration(milliseconds: 400)); // autoScroll starts
    await tester.pump(const Duration(milliseconds: 400)); // autoScroll lands
    await tester.pump(); // step tooltip at the right place
  }

  testWidgets('full tour flow: start → 4 steps → overlay removed',
      (tester) async {
    await pumpApp(tester);

    // Idle: no engine text in the tree.
    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip'), findsNothing);

    // Start the tour.
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump(); // frame 1: scrim (position snapshot post-frame)
    await tester.pump(); // step 1 tooltip at the right place

    // Step 1: the target is mounted → active right away (target wiring).
    expect(find.text('Quick log'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Step 2: the filter.
    await tester.tap(find.text('Next'));
    await tester.pump(); // new target: frame 1 — scrim, re-snapshot
    await tester.pump(); // step 2 tooltip
    expect(find.text('Daily filter'), findsOneWidget);

    // Step 3: the summary is not mounted yet → waiting phase (deferred
    // target).
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Summary card'), findsNothing);

    // The section "loads" after 600 ms — the target mounts (on small
    // screens possibly outside the painted area: no frozen spotlight, just
    // silence until the app scrolls it into view).
    await tester.pump(const Duration(milliseconds: 700)); // target mounted
    await tester.scrollUntilVisible(find.text('Summary'), 500);
    await tester.pump(); // active step: frame 1 — scrim (re-snapshot)
    await tester.pump(); // step 3 tooltip
    expect(find.text('Summary card'), findsOneWidget);
    expect(find.text('Preparing…'), findsNothing);

    // Step 4: the first entry.
    await tester.tap(find.text('Next'));
    await tester.pump(); // new target: scrim + re-snapshot
    await tester.pump(); // step 4 tooltip
    expect(find.text('Workout list'), findsOneWidget);

    // Done → idle: the overlay is removed, no engine text.
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    expect(find.text('Summary card'), findsNothing);
    expect(find.text('Workout list'), findsNothing);
  });

  testWidgets('versioned intro: once per version, re-shows after a bump',
      (tester) async {
    await pumpApp(tester);
    // The version card lives at the bottom of the demo list.
    await tester.scrollUntilVisible(find.text('Versioned intro'), 500);
    await tester.pump();
    expect(find.textContaining('will show again'), findsOneWidget);

    // Back to the top: the tour below runs in the standard viewport.
    await tester.scrollUntilVisible(find.text('Visual demos'), 500);
    await tester.pump();

    // First run: shows.
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump(); // frame 1: scrim (snapshot post-frame)
    await tester.pump(); // step 1 tooltip
    expect(find.text('Quick log'), findsOneWidget);

    // Exit (skip) → marked shown for 1.0.0. The version card may be out
    // of the built range after the scrolls above — scroll it back.
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    await tester.scrollUntilVisible(find.text('Versioned intro'), 500);
    await tester.pump();
    expect(
        find.textContaining('already showed in this version'), findsOneWidget);

    // Same version: gated — a snackbar explains, no tour starts.
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump();
    expect(find.textContaining('bump the version to see it again'),
        findsOneWidget);
    expect(find.text('Next'), findsNothing);

    // Version bump → the intro is available again.
    await tester.scrollUntilVisible(find.text('Bump version'), 500);
    await tester.pump();
    await tester.tap(find.text('Bump version'));
    await tester.pump();
    expect(find.textContaining('will show again'), findsOneWidget);
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Quick log'), findsOneWidget);

    // Reset → the intro will show again.
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Reset store'), 500);
    await tester.pump();
    await tester.tap(find.text('Reset store'));
    await tester.pump();
    expect(find.textContaining('will show again'), findsWidgets);
  });

  testWidgets('showHint: a single tip without a tour', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Show hint'));
    await tester.pump(); // frame 1: scrim (snapshot post-frame)
    await tester.pump(); // the tip tooltip

    expect(find.text('This is the quick-log button'), findsOneWidget);
    // A single hint keeps no action row (no Done) — a tap on the scrim
    // dismisses it.
    expect(find.text('Done'), findsNothing);
    expect(find.text('Next'), findsNothing);

    await tester.tapAt(const Offset(30, 100));
    await tester.pump();
    expect(find.text('This is the quick-log button'), findsNothing);
  });

  testWidgets('light/dark: toggling the theme does not break the app',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Toggle theme'));
    await tester.pump();
    expect(find.text('Hintful'), findsOneWidget); // the app is alive

    await tester.tap(find.byTooltip('Toggle theme'));
    await tester.pump();
    expect(find.text('Hintful'), findsOneWidget);
  });

  testWidgets('multi-target tour: several holes at once, then a single one',
      (tester) async {
    await pumpApp(tester);

    // The targets sit above the demo card: the engine auto-scrolls them in.
    await startTour(tester, 'Spotlight two targets');

    // Both filters are spotlighted — and both remain visible.
    expect(find.text('Both filters at once'), findsOneWidget);
    expect(find.text('All sets'), findsOneWidget);
    expect(find.text('By day'), findsOneWidget);

    await nextStep(tester);
    expect(find.text('Back to one target'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Back to one target'), findsNothing);
  });

  testWidgets(
      'multi-content: extra tooltips around one target, one control set',
      (tester) async {
    await pumpApp(tester);

    await startTour(tester, 'Tooltips around one target');

    expect(find.text('Primary tooltip'), findsOneWidget);
    expect(find.text('Left slot'), findsOneWidget);
    expect(find.text('Top slot'), findsOneWidget);
    // A single-step tour keeps no action row — not even on the primary.
    expect(find.text('Done'), findsNothing);
    expect(find.text('Next'), findsNothing);

    await tester.tapAt(const Offset(30, 100));
    await tester.pump();
    expect(find.text('Primary tooltip'), findsNothing);
  });

  testWidgets('tap regions: target vs overlay callbacks, overlay can be off',
      (tester) async {
    await pumpApp(tester);

    await startTour(tester, 'Tap target vs scrim');
    expect(find.text('Tap target vs overlay'), findsOneWidget);

    // Target tap → its own callback (with the position), no advance.
    await tester.tap(find.text('Log a set')); // the FAB (the target)
    await tester.pump();
    expect(find.textContaining('Target tap at'), findsOneWidget);
    expect(find.text('Tap target vs overlay'), findsOneWidget);

    // Overlay tap → its own callback, no advance either.
    await tester.tapAt(const Offset(30, 100)); // the scrim, top-left
    await tester.pump();
    expect(find.textContaining('Overlay tap'), findsOneWidget);
    expect(find.text('Tap target vs overlay'), findsOneWidget);

    // Step 2: overlay taps are turned off — the scrim ignores them.
    await nextStep(tester);
    expect(find.text('Overlay taps off'), findsOneWidget);

    // Free scrim area: auto-scroll parks entry-0 at the top (its hole spans
    // the full width up to y=128) and the tooltip sits above the middle —
    // this point is outside both, so only the overlay region answers.
    await tester.tapAt(const Offset(40, 500));
    await tester.pump();
    expect(find.text('Overlay taps off'), findsOneWidget); // still here
    expect(find.text('Done'), findsOneWidget); // the step did not advance

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Overlay taps off'), findsNothing);
  });

  testWidgets('offer dialog: accept starts the tour, then gated',
      (tester) async {
    await pumpApp(tester);

    await tapDemoButton(tester, 'Want a tour? dialog');
    await tester.pump(); // route push
    await tester.pump(const Duration(milliseconds: 300)); // dialog in
    expect(find.text('Want a tour?'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(); // step 1 tooltip

    // The tour runs like any other.
    expect(find.text('Quick log'), findsOneWidget);
    await nextStep(tester); // autoScroll brings the filters in
    expect(find.text('All sets filter'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('All sets filter'), findsNothing);

    // Accepted tours are marked shown on exit — no re-offer in this version.
    await tapDemoButton(tester, 'Want a tour? dialog');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Want a tour?'), findsNothing);
  });

  testWidgets('offer dialog: decline with "apply to all pages" is remembered',
      (tester) async {
    await pumpApp(tester);

    await tapDemoButton(tester, 'Want a tour? dialog');
    await tester.pump(); // route push
    await tester.pump(const Duration(milliseconds: 300)); // dialog in
    expect(find.text('Want a tour?'), findsOneWidget);

    await tester.tap(find.text('Apply to all pages'));
    await tester.pump();
    await tester.tap(find.text('Later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog out
    expect(find.text('Want a tour?'), findsNothing);

    // The decline (globally, via the checkbox) suppresses the offer.
    await tapDemoButton(tester, 'Want a tour? dialog');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Want a tour?'), findsNothing);
  });

  testWidgets('scrim style: pulse option does not break a tour',
      (tester) async {
    await pumpApp(tester);

    await tapDemoButton(tester, 'Pulse');
    await tester.pump();

    // The pulse animates forever — bounded pumps instead of pumpAndSettle.
    await startTour(tester, 'Spotlight two targets');
    expect(find.text('Both filters at once'), findsOneWidget);

    await nextStep(tester);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Both filters at once'), findsNothing);
  });

  testWidgets('custom animation: tooltipBuilder entry with its own button',
      (tester) async {
    await pumpApp(tester);

    await tapDemoButton(tester, 'Custom tooltip');
    await tester.pump(); // frame 1: scrim
    await tester.pump(); // tooltip
    expect(find.text('Fade and rise'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text('Fade and rise'), findsNothing);
  });

  testWidgets('json tour: parsed steps run like declared ones', (tester) async {
    await pumpApp(tester);

    await startTour(tester, 'Tour from JSON');
    expect(find.text('From JSON'), findsOneWidget);

    await nextStep(tester);
    expect(find.text('Second from JSON'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Second from JSON'), findsNothing);
  });
}
