import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/controller.dart';
import 'package:hintful/src/engine/labels.dart';
import 'package:hintful/src/engine/specs.dart';
import 'package:hintful/src/engine/store.dart';
import 'package:hintful/src/engine/theme/hint_theme.dart';
import 'package:hintful/src/widgets/tour_offer.dart';

HintTour _tour(String id, {String? minShowVersion}) => HintTour(
      id: id,
      steps: [
        HintStep(
          targetId: 'x',
          content: HintStepContent(title: 'X'),
        ),
      ],
      minShowVersion: minShowVersion,
    );

/// Rect-target tour: the headless machine enters HintActive immediately
/// (no registry, no wait timer) — the pump/dispose shape stays simple.
HintTour _rectTour(String id) => HintTour(
      id: id,
      steps: [
        HintStep(
          targetId: 'x',
          content: HintStepContent(title: 'X'),
          targetRect: const Rect.fromLTWH(10, 10, 50, 50),
        ),
      ],
    );

/// Headless controller wired to [store] — the offer always reads
/// controller.effectiveStore (no per-call store).
HintController _controllerWith(HintStore store) =>
    HintController(headless: true, store: store);

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
  testWidgets('labels default from HintTheme.tourOfferLabels', (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    const themed = HintTourOfferLabels(
      title: 'Themed offer',
      acceptLabel: 'Begin',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
                .copyWith(tourOfferLabels: themed),
          ],
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: _tour('t'),
    );
    await _pumpDialog(tester);

    expect(find.text('Themed offer'), findsOneWidget);
    expect(find.text('Begin'), findsOneWidget);
    // The unset fields keep their defaults — the theme replaces wholesale.
    expect(find.text('Later'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(await result, HintTourOfferResult.declined);
  });

  testWidgets('explicit labels: override the theme', (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    const themed = HintTourOfferLabels(title: 'Themed offer');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            HintTheme.minimal(ColorScheme.fromSeed(seedColor: Colors.teal))
                .copyWith(tourOfferLabels: themed),
          ],
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: _tour('t'),
      labels: const HintTourOfferLabels(title: 'Explicit offer'),
    );
    await _pumpDialog(tester);

    expect(find.text('Explicit offer'), findsOneWidget);
    expect(find.text('Themed offer'), findsNothing);

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(await result, HintTourOfferResult.declined);
  });

  testWidgets('accept starts the tour', (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
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
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t', minShowVersion: '1.0.0');
    store.markShown('t', '1.0.0');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      pageId: 'Home',
    );
    await _pumpDialog(tester);

    expect(find.text('Want a tour?'), findsNothing);
    expect(await result, HintTourOfferResult.alreadyShown);
    expect(controller.currentState.isIdle, isTrue);
  });

  testWidgets('decline: remembered per page, other pages still offer',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    var result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
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

    // The same page no longer offers → alreadyShown…
    result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      pageId: 'Home',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsNothing);
    expect(await result, HintTourOfferResult.alreadyShown);

    // …a different page still does.
    result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      pageId: 'Other',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsOneWidget);
  });

  testWidgets('decline with "apply to all pages": remembered globally',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
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
      pageId: 'Other',
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsNothing);
    expect(await result2, HintTourOfferResult.alreadyShown);
  });

  testWidgets('a decline does not suppress the tour from other entry points',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
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

  testWidgets('pageId omitted — decline key defaults to tour.id',
      (tester) async {
    final store = InMemoryHintStore();
    final controller = _controllerWith(store);
    addTearDown(controller.dispose);
    final context = await _pumpApp(tester);
    final tour = _tour('t');

    final result = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
      // pageId omitted → tour.id
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(await result, HintTourOfferResult.declined);
    expect(store.shouldShow('offer:t@t'), isFalse,
        reason: 'per-page key uses tour.id as the default page');
    expect(store.shouldShow('offer:t'), isTrue);

    // Same default page no longer offers.
    final again = showHintTourOffer(
      context: context,
      controller: controller,
      tour: tour,
    );
    await _pumpDialog(tester);
    expect(find.text('Want a tour?'), findsNothing);
    expect(await again, HintTourOfferResult.alreadyShown);
  });

  group('HintMarkPolicy (offer accept path)', () {
    testWidgets('onFinish (default): accept + finish → marked shown',
        (tester) async {
      final store = InMemoryHintStore();
      final controller = _controllerWith(store);
      addTearDown(controller.dispose);
      final context = await _pumpApp(tester);

      final result = showHintTourOffer(
        context: context,
        controller: controller,
        tour: _rectTour('t'),
        pageId: 'Home',
      );
      await _pumpDialog(tester);
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(await result, HintTourOfferResult.started);
      expect(controller.currentState.isIdle, isFalse);

      controller.next(); // single step → finish
      expect(controller.currentState.isIdle, isTrue);
      expect(store.shouldShow('t'), isFalse,
          reason: 'finish marks the tour shown');
    });

    testWidgets('onFinish (default): accept + skip → not marked',
        (tester) async {
      final store = InMemoryHintStore();
      final controller = _controllerWith(store);
      addTearDown(controller.dispose);
      final context = await _pumpApp(tester);

      final result = showHintTourOffer(
        context: context,
        controller: controller,
        tour: _rectTour('t'),
        pageId: 'Home',
      );
      await _pumpDialog(tester);
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(await result, HintTourOfferResult.started);
      controller.skip();
      expect(controller.currentState.isIdle, isTrue);
      expect(store.shouldShow('t'), isTrue,
          reason: 'skip must not record — the tour may show again');
    });

    testWidgets('manual: finish → not marked (app owns the shown-state)',
        (tester) async {
      final store = InMemoryHintStore();
      final controller = _controllerWith(store);
      addTearDown(controller.dispose);
      final context = await _pumpApp(tester);

      final result = showHintTourOffer(
        context: context,
        controller: controller,
        tour: _rectTour('t'),
        pageId: 'Home',
        mark: HintMarkPolicy.manual,
      );
      await _pumpDialog(tester);
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(await result, HintTourOfferResult.started);
      controller.next();
      expect(controller.currentState.isIdle, isTrue);
      expect(store.shouldShow('t'), isTrue,
          reason: 'manual: the app records the shown-state itself');
    });

    testWidgets('onAnyExit: accept + skip → marked shown', (tester) async {
      final store = InMemoryHintStore();
      final controller = _controllerWith(store);
      addTearDown(controller.dispose);
      final context = await _pumpApp(tester);

      final result = showHintTourOffer(
        context: context,
        controller: controller,
        tour: _rectTour('t'),
        pageId: 'Home',
        mark: HintMarkPolicy.onAnyExit,
      );
      await _pumpDialog(tester);
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(await result, HintTourOfferResult.started);
      controller.skip();
      expect(controller.currentState.isIdle, isTrue);
      expect(store.shouldShow('t'), isFalse,
          reason: 'onAnyExit marks even on skip');
    });

    testWidgets('busy controller → the offer accept asserts (debug contract)',
        (tester) async {
      final store = InMemoryHintStore();
      final controller = _controllerWith(store);
      addTearDown(controller.dispose);
      final context = await _pumpApp(tester);

      await controller.start(_rectTour('other')); // one tour at a time

      final result = showHintTourOffer(
        context: context,
        controller: controller,
        tour: _rectTour('t'),
        pageId: 'Home',
      );
      await _pumpDialog(tester);
      expect(find.text('Want a tour?'), findsOneWidget);

      // Attach the matcher BEFORE the tap: the assert fires in the offer's
      // async continuation during the pump, and an unlistened future would
      // report the error as unhandled first.
      final expectation = expectLater(result, throwsAssertionError);
      await tester.tap(find.text('Start'));
      await tester.pump();
      await expectation;

      expect(store.shouldShow('t'), isTrue,
          reason: 'the rejected accept must not mark anything');
    });
  });
}
