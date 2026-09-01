import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/position_resolver.dart';

/// Classic scene: the target (leader) and a follower in one Stack — as in the
/// engine.
Widget _harness({required LayerLink link, required Widget followerChild}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 40,
            top: 60,
            child: CompositedTransformTarget(
              link: link,
              child: Container(width: 100, height: 50, color: Colors.red),
            ),
          ),
          Positioned.fill(child: followerChild),
        ],
      ),
    ),
  );
}

Future<CompositorPositionResolver> _resolverInside(WidgetTester tester) async {
  late CompositorPositionResolver resolver;
  final link = LayerLink();
  await tester.pumpWidget(_harness(
    link: link,
    followerChild: CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      child: Builder(
        builder: (context) {
          final follower =
              context.findAncestorRenderObjectOfType<RenderFollowerLayer>()!;
          resolver = CompositorPositionResolver(follower);
          return const SizedBox.expand();
        },
      ),
    ),
  ));
  return resolver;
}

void main() {
  group('CompositorPositionResolver', () {
    testWidgets('translation = target global position, size = its size',
        (tester) async {
      final resolver = await _resolverInside(tester);
      await tester.pump(); // the scene is built — _lastTransform is filled

      final position = resolver.resolve();
      expect(position, isA<PositionedTarget>());
      final p = position as PositionedTarget;
      expect(p.translation, const Offset(40, 60));
      expect(p.size, const Size(100, 50));

      // Cross-check against the framework: translation is the real position.
      final actual = tester.getTopLeft(find.byType(Container));
      expect(p.translation.dx, closeTo(actual.dx, 0.1));
      expect(p.translation.dy, closeTo(actual.dy, 0.1));
    });

    testWidgets('scroll: translation follows the target from the compositor',
        (tester) async {
      final link = LayerLink();
      late CompositorPositionResolver resolver;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ListView(
                  children: [
                    const SizedBox(height: 400),
                    CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(
                        width: 200,
                        height: 80,
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
              ),
              Positioned.fill(
                child: CompositedTransformFollower(
                  link: link,
                  showWhenUnlinked: false,
                  child: Builder(
                    builder: (context) {
                      final follower = context.findAncestorRenderObjectOfType<
                          RenderFollowerLayer>()!;
                      resolver = CompositorPositionResolver(follower);
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      final before = resolver.resolve();
      expect(before, isA<PositionedTarget>());

      // Scroll 60 up via the scroll position: the compositor itself
      // recomputes the leader's position — no engine tracking code.
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .jumpTo(60);
      await tester.pump();

      final after = resolver.resolve();
      expect(after, isA<PositionedTarget>());
      final beforePos = before as PositionedTarget;
      final afterPos = after as PositionedTarget;
      expect(
        afterPos.translation.dy,
        closeTo(beforePos.translation.dy - 60, 0.2),
      );
      expect(afterPos.translation.dx, closeTo(beforePos.translation.dx, 0.2));
      expect(afterPos.size, beforePos.size);
    });
  });

  group('UnlinkedTargetResolver', () {
    testWidgets('without a leader — UnlinkedTarget (target not mounted)',
        (tester) async {
      // A bare render object without a tree: the layer is not created (or no
      // transform has arrived) — no position from the compositor, like an
      // unregistered target.
      final follower = RenderFollowerLayer(
        link: LayerLink(),
        showWhenUnlinked: false,
      );
      final resolver = CompositorPositionResolver(follower);
      expect(resolver.resolve(), isA<UnlinkedTarget>());
    });
  });
}
