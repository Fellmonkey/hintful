import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/registry.dart';

/// Registration needs a BuildContext; the harness takes a live one from the
/// tree.
Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    Builder(
      builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      },
    ),
  );
  return captured;
}

void main() {
  testWidgets('registration → lookup/ids; unregister by the owner — clean',
      (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    final r =
        TargetRegistration(id: 'filters', link: LayerLink(), context: ctx);

    registry.register(r);
    expect(registry.lookup('filters'), same(r));
    expect(registry.ids, {'filters'});

    registry.unregister(r);
    expect(registry.lookup('filters'), isNull);
    expect(registry.ids, isEmpty);
  });

  testWidgets('listeners: notified on every real change, a no-op does not fire',
      (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    final r = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);

    var changes = 0;
    registry.addListener(() => changes++);

    registry.register(r);
    expect(changes, 1);

    registry.unregister(r);
    expect(changes, 2);

    registry.unregister(r); // a double unregister — no-op
    expect(changes, 2);
  });

  testWidgets(
      'multiple listeners; removeListener unsubscribes; '
      'subscribing twice — no-op', (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    final r = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);

    var first = 0;
    var second = 0;
    void l1() => first++;
    void l2() => second++;
    registry.addListener(l1);
    registry.addListener(l2);
    registry.addListener(l1); // Set: a duplicate — no-op

    registry.register(r);
    expect(first, 1);
    expect(second, 1);

    registry.removeListener(l1);
    registry.removeListener(l1); // a double unsubscribe — no-op
    registry.unregister(r);
    expect(first, 1, reason: 'unsubscribed — not notified');
    expect(second, 2);
  });

  testWidgets('duplicate id: the last one wins + warning', (tester) async {
    final ctx = await _pumpContext(tester);
    final warnings = <String>[];
    final registry = TargetRegistry(onWarning: warnings.add);
    final r1 = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);
    final r2 = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);

    registry.register(r1);
    registry.register(r2);

    expect(registry.lookup('a'), same(r2));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains("'a'"));
  });

  testWidgets("unregistering an old instance does not remove the new one",
      (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    final r1 = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);
    final r2 = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);

    registry.register(r1);
    registry.register(r2);

    var changes = 0;
    registry.addListener(() => changes++);

    registry.unregister(r1); // r1 is not the owner (r2 is) → no-op
    expect(changes, 0);
    expect(registry.lookup('a'), same(r2));

    registry.unregister(r2); // the owner → removal
    expect(changes, 1);
    expect(registry.lookup('a'), isNull);
  });

  testWidgets('an unknown registration — silent no-op', (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    final r1 = TargetRegistration(id: 'a', link: LayerLink(), context: ctx);
    final r2 = TargetRegistration(id: 'b', link: LayerLink(), context: ctx);

    registry.register(r1);
    var changes = 0;
    registry.addListener(() => changes++);

    registry.unregister(r2); // never registered
    expect(changes, 0);
    expect(registry.lookup('a'), same(r1));
  });

  testWidgets('ids — an immutable copy', (tester) async {
    final ctx = await _pumpContext(tester);
    final registry = TargetRegistry();
    registry.register(
      TargetRegistration(id: 'a', link: LayerLink(), context: ctx),
    );

    expect(() => registry.ids.add('x'), throwsUnsupportedError);
    expect(registry.ids, {'a'});
  });

  test('defaultInstance is reachable and independent of new instances', () {
    final a = TargetRegistry.defaultInstance;
    final b = TargetRegistry();
    expect(identical(a, b), isFalse);
    expect(a.ids, isEmpty);
    expect(b.ids, isEmpty);
  });
}
