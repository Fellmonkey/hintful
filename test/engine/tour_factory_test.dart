import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/specs.dart';
import 'package:hintful/engine/tour_factory.dart';

void main() {
  group('HintTour JSON round-trip', () {
    test('toJson/fromJson preserves id, steps, timeout, disableBackButton', () {
      final tour = HintTour(
        id: 'server',
        steps: [
          HintStep(targetId: 'a', title: 'Hello', description: 'World', position: TooltipPosition.bottom),
          HintStep(
            targetId: 'b',
            title: 'Second',
            moreTargets: ['c'],
            moreTooltips: [HintTooltip(position: TooltipPosition.top, title: 'Extra')],
            position: TooltipPosition.top,
            waitTimeout: const Duration(milliseconds: 500),
            showSkip: false,
          ),
        ],
        stepTimeout: const Duration(seconds: 5),
        disableBackButton: true,
      );
      final json = tour.toJson();
      final back = HintTour.fromJson(json);
      expect(back.id, tour.id);
      expect(back.steps.length, tour.steps.length);
      expect(back.steps[0].targetId, 'a');
      expect(back.steps[0].title, 'Hello');
      expect(back.steps[0].position, TooltipPosition.bottom);
      expect(back.steps[1].moreTargets, ['c']);
      expect(back.steps[1].moreTooltips.first.position, TooltipPosition.top);
      expect(back.steps[1].waitTimeout, const Duration(milliseconds: 500));
      expect(back.steps[1].showSkip, false);
      expect(back.stepTimeout, const Duration(seconds: 5));
      expect(back.disableBackButton, true);
      // json string round-trip
      final s = jsonEncode(json);
      final back2 = HintTour.fromJson(jsonDecode(s) as Map<String, dynamic>);
      expect(back2.id, 'server');
    });

    test('HintTooltip toJson/fromJson', () {
      final t = HintTooltip(position: TooltipPosition.left, title: 'T', description: 'D');
      final back = HintTooltip.fromJson(t.toJson());
      expect(back.position, TooltipPosition.left);
      expect(back.title, 'T');
    });
  });

  group('HintTourFactory', () {
    test('InMemory fetch', () async {
      final tour = HintTour(id: 'a', steps: [HintStep(targetId: 'x', title: 'X')]);
      final f = InMemoryHintTourFactory({'a': tour});
      expect((await f.fetch('a')).id, 'a');
      expect(() => f.fetch('missing'), throwsA(isA<StateError>()));
    });

    test('Fetcher fetch via mock fetcher', () async {
      final tour = HintTour(id: 'remote', steps: [HintStep(targetId: 'y', title: 'Y')]);
      final f = FetcherHintTourFactory(
        baseUrl: 'https://cdn.example.com/tours',
        fetcher: (uri) async {
          expect(uri.toString(), 'https://cdn.example.com/tours/remote.json');
          return jsonEncode(tour.toJson());
        },
      );
      final back = await f.fetch('remote');
      expect(back.id, 'remote');
      expect(back.steps.first.targetId, 'y');
    });

    test('Fetcher throws on non-200 body (simulated by fetcher throw)', () async {
      final f = FetcherHintTourFactory(
        baseUrl: 'https://cdn.example.com/tours',
        fetcher: (_) async => throw StateError('404'),
      );
      expect(() => f.fetch('nope'), throwsA(isA<StateError>()));
    });
  });
}
