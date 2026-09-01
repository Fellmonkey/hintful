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
  /// resolves → setState → the demo card shows the real status).
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump();
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

    // The section "loads" after 600 ms → the target appearing activates the
    // step.
    await tester.pump(const Duration(milliseconds: 700)); // target mounted
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
    expect(find.textContaining('will show again'), findsOneWidget);

    // First run: shows.
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump(); // frame 1: scrim (snapshot post-frame)
    await tester.pump(); // step 1 tooltip
    expect(find.text('Quick log'), findsOneWidget);

    // Exit (skip) → marked shown for 1.0.0.
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    expect(
        find.textContaining('already showed in this version'), findsOneWidget);

    // Same version: gated — a snackbar explains, no tour starts.
    await tester.tap(find.byTooltip('Show tour'));
    await tester.pump();
    expect(find.textContaining('bump the version to see it again'),
        findsOneWidget);
    expect(find.text('Next'), findsNothing);

    // Version bump → the intro is available again.
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
    expect(find.text('Done'), findsOneWidget); // 1 step = last

    await tester.tap(find.text('Done'));
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
}
