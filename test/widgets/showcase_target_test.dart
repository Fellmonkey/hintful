import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/registry.dart';
import 'package:hintful/widgets/showcase_target.dart';

Widget _app(Widget body) => MaterialApp(home: Scaffold(body: body));

void main() {
  group('registration lifecycle', () {
    testWidgets('mount registers, dispose unregisters', (tester) async {
      final registry = TargetRegistry();

      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'stats', registry: registry, child: const Text('c')),
      ));

      final registration = registry.lookup('stats');
      expect(registration, isNotNull);
      // The link reference — the same one the leader in the tree holds (the
      // follower will track exactly this link).
      final leader = tester.widget<CompositedTransformTarget>(
        find.byType(CompositedTransformTarget),
      );
      expect(leader.link, same(registration!.link));

      await tester.pumpWidget(_app(const SizedBox()));
      expect(registry.lookup('stats'), isNull);
      expect(registry.ids, isEmpty);
    });

    testWidgets(
        'a changed id re-registers: the old one is removed, the new one is '
        'in place', (tester) async {
      final registry = TargetRegistry();

      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'stats', registry: registry, child: const Text('c')),
      ));
      final first = registry.lookup('stats');
      expect(first, isNotNull);

      await tester.pumpWidget(_app(
        ShowcaseTarget(
            id: 'filters', registry: registry, child: const Text('c')),
      ));

      expect(registry.lookup('stats'), isNull); // the old id is removed
      final second = registry.lookup('filters');
      expect(second, isNotNull);
      // A new target entity = a new link (not a reused one).
      expect(second!.link, isNot(same(first!.link)));
    });

    testWidgets('only a changed child/label — the same registration',
        (tester) async {
      final registry = TargetRegistry();

      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'stats', registry: registry, child: const Text('a')),
      ));
      final first = registry.lookup('stats');

      await tester.pumpWidget(_app(
        ShowcaseTarget(
          id: 'stats',
          registry: registry,
          semanticsLabel: 'Label',
          child: const Text('b'),
        ),
      ));

      expect(registry.lookup('stats'), same(first));
    });

    testWidgets(
        'a changed registry: removed from the old one, registered '
        'into the new one', (tester) async {
      final registryA = TargetRegistry();
      final registryB = TargetRegistry();

      await tester.pumpWidget(_app(
        ShowcaseTarget(
            id: 'stats', registry: registryA, child: const Text('c')),
      ));
      expect(registryA.lookup('stats'), isNotNull);

      await tester.pumpWidget(_app(
        ShowcaseTarget(
            id: 'stats', registry: registryB, child: const Text('c')),
      ));

      expect(registryA.lookup('stats'), isNull); // no leak in the old one
      expect(registryB.lookup('stats'), isNotNull);
    });

    testWidgets(
        'recreation with the same id (ListView rebuild): the last one owns '
        'the id, the dispose of the old one does not remove it',
        (tester) async {
      final registry = TargetRegistry();
      final child = const Text('c');

      Widget app(Key key) => _app(
            ShowcaseTarget(
              key: key,
              id: 'stats',
              registry: registry,
              child: child,
            ),
          );

      await tester.pumpWidget(app(const ValueKey('first')));
      final first = registry.lookup('stats');
      expect(first, isNotNull);

      await tester.pumpWidget(app(const ValueKey('second')));

      final second = registry.lookup('stats');
      expect(second, isNotNull);
      expect(identical(second, first), isFalse);
      // The dispose of the old State already ran (it would have unregistered
      // by identity — it did not): the fresh registration stays the owner.
      expect(registry.lookup('stats'), same(second));
    });
  });

  group('rendering', () {
    testWidgets('the child renders 1:1 through the leader; idle — no overlay',
        (tester) async {
      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'stats', child: const Text('content')),
      ));

      expect(find.text('content'), findsOneWidget);
      expect(find.byType(CompositedTransformTarget), findsOneWidget);
      // The widget part of the zero-idle guarantee: outside a tour the tree
      // holds no engine-overlay widget, only the target (leader) itself.
      expect(find.byType(CompositedTransformFollower), findsNothing);
    });

    testWidgets('semanticsLabel: a Semantics wrapper only with a label set',
        (tester) async {
      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'stats', child: const Text('x')),
      ));
      expect(
        find.descendant(
          of: find.byType(ShowcaseTarget),
          matching: find.byType(Semantics),
        ),
        findsNothing,
      );

      await tester.pumpWidget(_app(
        ShowcaseTarget(
          id: 'stats',
          semanticsLabel: 'Save button',
          child: const Text('x'),
        ),
      ));
      expect(
        find.descendant(
          of: find.byType(ShowcaseTarget),
          matching: find.byType(Semantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets('without registry: — the default singleton (zero-config)',
        (tester) async {
      final singleton = TargetRegistry.defaultInstance;

      await tester.pumpWidget(_app(
        ShowcaseTarget(id: 'zero-config', child: const Text('x')),
      ));
      expect(singleton.lookup('zero-config'), isNotNull);

      await tester.pumpWidget(_app(const SizedBox()));
      expect(singleton.lookup('zero-config'), isNull); // dispose cleaned up
      expect(singleton.ids, isEmpty);
    });
  });
}
