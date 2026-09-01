import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/controller.dart';
import 'package:hintful/engine/specs.dart';
import 'package:hintful/engine/store.dart';
import 'package:hintful/widgets/tour_offer.dart';

HintTour _tour(String id) => HintTour(
      id: id,
      steps: [HintStep(targetId: 'x', title: 'X')],
    );

/// A MaterialApp + a context under it (the dialog needs a Navigator).
Future<BuildContext> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: SizedBox())),
  );
  return tester.element(find.byType(Scaffold));
}

/// Pump a just-started offer dialog open (route push + entry animation).
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump(); // route push
  await tester.pump(const Duration(milliseconds: 300)); // dialog animation
}

void main() {
  testWidgets('accept starts the tour', (tester) async {
    final store = InMemoryHintStore();
    final controller = HintController();
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(await result, HintTourOfferResult.started);
    expect(controller.currentState.isIdle, isFalse,
        reason: 'the tour started (headless machine)');
    // The started tour armed a wait-for-target timer — dispose in the body
    // (a tearDown would run after the pending-timer check).
    controller.dispose();
  });

  testWidgets(
      'the dialog is skipped when the tour already ran for the '
      'version', (tester) async {
    final store = InMemoryHintStore();
    final controller = HintController();
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');
    store.markShown('t', '1.0.0');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
      minVersion: '1.0.0',
    );
    await _pumpDialog(tester);

    expect(find.text('Want a tour?'), findsNothing);
    expect(await result, HintTourOfferResult.declined);
    expect(controller.currentState.isIdle, isTrue);
  });

  testWidgets('decline: remembered per page, other pages still offer',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = HintController();
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    var result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();

    expect(await result, HintTourOfferResult.declined);
    expect(store.shouldShow('offer:t@Home'), isFalse,
        reason: 'the per-page decline is recorded');
    expect(store.shouldShow('offer:t'), isTrue,
        reason: 'no global decline without the checkbox');

    // The same page no longer offers…
    result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsNothing);
    expect(await result, HintTourOfferResult.declined);

    // …a different page still does.
    result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Other',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsOneWidget);
  });

  testWidgets('decline with "apply to all pages": remembered globally',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = HintController();
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    await tester.tap(find.text('Apply to all pages'));
    await tester.pump();
    await tester.tap(find.text('Later'));
    await tester.pump();

    expect(await result, HintTourOfferResult.declined);
    expect(store.shouldShow('offer:t@Home'), isFalse);
    expect(store.shouldShow('offer:t'), isFalse,
        reason: 'the checkbox records a global decline');

    // Any other page is suppressed too.
    final result2 = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Other',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsNothing);
    expect(await result2, HintTourOfferResult.declined);
  });

  testWidgets('a decline does not suppress the tour from other entry points',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = HintController();
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      store: store,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(await result, HintTourOfferResult.declined);

    // The tour's own shown-state key is untouched — a manual start (e.g. a
    // settings button) still works.
    expect(store.shouldShow('t'), isTrue);
  });
}
