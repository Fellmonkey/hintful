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

  group('unknown payload values fall back instead of throwing', () {
    test('every enum field falls back to its default and warns', () {
      final warnings = <String>[];
      final tour = HintTour.fromJson(
        {
          'id': 'server',
          'missingTargetPolicy': 'explode',
          'steps': [
            {
              'targetId': 'a',
              'title': 'Hello',
              'position': 'middle',
              'focusShape': 'hexagon',
              'transitionCurve': 'wobble',
              'missingTargetPolicy': 'explode-too',
              'moreTooltips': [
                {'position': 'sideways', 'title': 'Extra'},
              ],
            },
          ],
        },
        onWarning: warnings.add,
      );

      final step = tour.steps.single;
      expect(tour.missingTargetPolicy, HintMissingTargetPolicy.abortTour);
      expect(step.position, TooltipPosition.auto);
      expect(step.focusShape, isNull); // unknown → inherit the target's
      expect(step.transitionCurve, isNull); // unknown → no entry animation
      expect(step.missingTargetPolicy, isNull); // unknown → inherit the tour's
      expect(step.moreTooltips.single.position, TooltipPosition.auto);
      expect(step.moreTooltips.single.title, 'Extra'); // the rest survives
      expect(warnings, hasLength(6));
      expect(warnings.every((w) => w.startsWith('hintful: unknown ')), isTrue);
      // The order follows argument evaluation — assert membership, not order.
      expect(warnings.any((w) => w.contains("missingTargetPolicy 'explode'")),
          isTrue);
      expect(warnings.any((w) => w.contains("transitionCurve 'wobble'")), isTrue);
    });

    test('an absent field is not a warning', () {
      final warnings = <String>[];
      final tour = HintTour.fromJson(
        {
          'id': 'minimal',
          'steps': [
            {'targetId': 'a', 'title': 'A'},
          ],
        },
        onWarning: warnings.add,
      );
      expect(tour.steps.single.position, TooltipPosition.auto);
      expect(tour.steps.single.transitionCurve, isNull);
      expect(warnings, isEmpty);
    });

    test('FetcherHintTourFactory threads onWarning to the parser', () async {
      final warnings = <String>[];
      final f = FetcherHintTourFactory(
        baseUrl: 'https://cdn.example.com/tours',
        fetcher: (_) async => jsonEncode({
          'id': 'remote',
          'steps': [
            {'targetId': 'a', 'title': 'A', 'position': 'middle'},
          ],
        }),
        onWarning: warnings.add,
      );

      final tour = await f.fetch('remote');
      expect(tour.steps.single.position, TooltipPosition.auto);
      expect(warnings.single, contains("position 'middle'"));
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
