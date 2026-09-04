import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/specs.dart';
import 'package:hintful/engine/theme/hint_theme.dart';
import 'package:hintful/widgets/default_tooltip.dart';

class _FakeActions implements HintActions {
  int nextCalls = 0;
  int previousCalls = 0;
  int skipCalls = 0;
  int finishCalls = 0;

  @override
  void next() => nextCalls++;

  @override
  void previous() => previousCalls++;

  @override
  void skip() => skipCalls++;

  @override
  void finish() => finishCalls++;
}

HintTooltipContext _ctx(
  _FakeActions actions,
  int stepIndex,
  int totalSteps,
) =>
    HintTooltipContext(
      actions: actions,
      stepIndex: stepIndex,
      totalSteps: totalSteps,
    );

Widget _wrap(
  Widget child, {
  List<ThemeExtension<dynamic>>? extensions,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      extensions: extensions,
    ),
    home: Scaffold(
      body: MediaQuery(
        // Keep the default test surface size — a zero-size MediaQueryData
        // would collapse the tooltip's maxWidth (screenSize.width - 32) and
        // overflow the button row.
        data: MediaQueryData(
          size: const Size(800, 600),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Center(child: child),
      ),
    ),
  );
}

void main() {
  final step = HintStep(
    targetId: 'stats',
    title: 'Title',
    description: 'Description',
  );

  testWidgets('title/description + Next/Skip (not the last step)',
      (tester) async {
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(_FakeActions(), 0, 2),
    )));

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('last step: Done instead of Next, no Skip; Done → finish',
      (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(actions, 1, 2),
    )));

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    // The tour is about to end anyway — a Skip next to Done is redundant
    // (Done does the same thing).
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Done'));
    expect(actions.finishCalls, 1);
  });

  testWidgets('Next → next, Skip → skip', (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(actions, 0, 2),
    )));

    await tester.tap(find.text('Next'));
    expect(actions.nextCalls, 1);

    await tester.tap(find.text('Skip'));
    expect(actions.skipCalls, 1);
  });

  testWidgets(
      'Back: hidden on the first step, shown from step 2; '
      'Back → previous', (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(actions, 0, 2),
    )));
    expect(find.text('Back'), findsNothing);

    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(actions, 1, 2),
    )));
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    expect(actions.previousCalls, 1);
  });

  testWidgets('Skip: at the far left edge, smaller than the primary action',
      (tester) async {
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      // Step 2 of 3: an intermediate step — Back, Skip and Next are all on
      // stage (on the last step Skip is hidden: Done does the same).
      ctx: _ctx(_FakeActions(), 1, 3),
    )));

    final skip = tester.getRect(find.text('Skip'));
    final back = tester.getRect(find.text('Back'));
    final next = tester.getRect(find.text('Next'));

    // Skip is the leftmost control — away from the Back/Next group.
    expect(skip.left, lessThan(back.left));
    expect(skip.left, lessThan(next.left));
    // …and visually smaller than the primary action (accidental-tap
    // protection: a tap aimed at Next must not land on Skip).
    expect(skip.width, lessThan(next.width));
    expect(skip.height, lessThan(next.height));
  });

  testWidgets('single-step tour: no Skip (a lone Skip is meaningless)',
      (tester) async {
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      // totalSteps == 1: a single hint — Skip is hidden even though the
      // step's showSkip defaults to true (Done does the same thing).
      ctx: _ctx(_FakeActions(), 0, 1),
    )));

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('showSkip: false — no Skip button', (tester) async {
    final noSkip = HintStep(targetId: 'stats', title: 't', showSkip: false);
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: noSkip,
      ctx: _ctx(_FakeActions(), 0, 1),
    )));

    expect(find.text('Skip'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('text scale 1.0: no scrollable is built (content grows '
      'freely, width still capped)', (tester) async {
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(_FakeActions(), 0, 2),
    )));

    // The scroll machinery is ~18 KB of heap while mounted — at scale 1.0
    // the content is width-capped (wrapping) and grows freely instead.
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('text scale 2.0: height-capped and scrollable — the contract',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DefaultTooltip(
        step: step,
        ctx: _ctx(_FakeActions(), 0, 2),
      ),
      textScale: 2.0,
    ));

    // At the 2.0 text scale the content must still fit on screen: capped
    // height + scroll instead of overflow.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('buttons expose the button role + tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(_FakeActions(), 0, 2),
    )));

    final skip = tester.getSemantics(find.text('Skip')).getSemanticsData();
    expect(skip.flagsCollection.isButton, isTrue);
    expect(skip.hasAction(SemanticsAction.tap), isTrue);
    final next = tester.getSemantics(find.text('Next')).getSemanticsData();
    expect(next.flagsCollection.isButton, isTrue);
    expect(next.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('semantics "Step N of M: …"', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(_FakeActions(), 0, 3),
    )));

    // The container announces "Step N of M: <title>"; the inner text keeps
    // its own node (exposed separately once the content is scrollable), so
    // assert the container label exactly.
    expect(
      find.bySemanticsLabel(RegExp(r'Step 1 of 3: Title')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('custom theme: colors/radius from HintTheme', (tester) async {
    const custom = HintTheme(
      tooltipBackground: Color(0xFF103355),
      tooltipForeground: Color(0xFFEEEEEE),
      scrimColor: Color(0x80000000),
      tooltipRadius: BorderRadius.all(Radius.circular(4)),
      tooltipPadding: EdgeInsets.all(8),
    );
    await tester.pumpWidget(_wrap(
      DefaultTooltip(
        step: step,
        ctx: _ctx(_FakeActions(), 0, 1),
      ),
      extensions: [custom],
    ));

    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Title'), matching: find.byType(Material))
          .first,
    );
    expect(material.color, const Color(0xFF103355));
    // Material(borderRadius:) keeps shape == null and draws a
    // RoundedRectangleBorder at paint time — we check borderRadius.
    expect(material.borderRadius, const BorderRadius.all(Radius.circular(4)));
    // No styles in the custom theme — the default from tooltipForeground.
    final title = tester.widget<Text>(find.text('Title'));
    expect(title.style?.color, const Color(0xFFEEEEEE));
  });

  testWidgets(
      'without a registered theme — defaults from ColorScheme '
      '(zero-config)', (tester) async {
    const seed = Colors.teal;
    await tester.pumpWidget(_wrap(DefaultTooltip(
      step: step,
      ctx: _ctx(_FakeActions(), 0, 1),
    )));

    final scheme = ColorScheme.fromSeed(seedColor: seed);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Title'), matching: find.byType(Material))
          .first,
    );
    // A ColorScheme inverseSurface pair, not a hardcoded "library" color.
    expect(material.color, scheme.inverseSurface);
    expect(material.color, isNot(Colors.white));
  });
}
