import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/specs.dart';

enum _TourStep { drawer, settings, records }

HintStep _stepFor(_TourStep step) => switch (step) {
      _TourStep.drawer => HintStep(targetId: 'drawer', title: 'Drawer'),
      _TourStep.settings => HintStep(targetId: 'settings', title: 'Settings'),
      _TourStep.records => HintStep(targetId: 'records', title: 'Records'),
    };

void main() {
  group('HintTour.fromEnum', () {
    test('steps follow the enum declaration order', () {
      final tour = HintTour.fromEnum(
        id: 'home',
        values: _TourStep.values,
        stepFor: _stepFor,
      );

      expect(tour.id, 'home');
      expect(
        [for (final s in tour.steps) s.targetId],
        ['drawer', 'settings', 'records'],
      );
    });

    test('stepFor maps each value to its own step content', () {
      final tour = HintTour.fromEnum(
        id: 'home',
        values: _TourStep.values,
        stepFor: _stepFor,
      );

      expect(tour.steps[0].title, 'Drawer');
      expect(tour.steps[1].title, 'Settings');
      expect(tour.steps[2].title, 'Records');
    });

    test('stepTimeout and disableBackButton pass through', () {
      final tour = HintTour.fromEnum(
        id: 'home',
        values: _TourStep.values,
        stepFor: _stepFor,
        stepTimeout: const Duration(seconds: 7),
        disableBackButton: true,
      );

      expect(tour.stepTimeout, const Duration(seconds: 7));
      expect(tour.disableBackButton, isTrue);
    });

    test('missingTargetPolicy passes through fromEnum', () {
      final tour = HintTour.fromEnum(
        id: 'home',
        values: _TourStep.values,
        stepFor: _stepFor,
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
      );

      expect(
        tour.missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
      );
    });

    test('the built tour participates in duplicate detection', () {
      final tour = HintTour.fromEnum(
        id: 'dup',
        values: _TourStep.values,
        stepFor: (step) => HintStep(
          // Every step spotlighting the same target — a tour-authoring
          // error the engine would flag at start.
          targetId: 'x',
          title: step.name,
        ),
      );

      expect(tour.duplicateTargetIds, {'x'});
    });

    test('empty values produce an empty-steps assertion (base contract)', () {
      // The base constructor asserts steps.length > 0; fromEnum with no
      // values hits the same contract.
      expect(
        () => HintTour.fromEnum<Never>(
          id: 'empty',
          values: const [],
          stepFor: (value) => throw UnimplementedError(),
        ),
        throwsAssertionError,
      );
    });
  });

  group('missingTargetPolicy JSON round-trip', () {
    test('tour + step policies survive toJson/fromJson', () {
      final tour = HintTour(
        id: 't',
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
        steps: const [
          HintStep(
            targetId: 'a',
            title: 'A',
            missingTargetPolicy: HintMissingTargetPolicy.skipStep,
          ),
          HintStep(targetId: 'b', title: 'B'),
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());

      expect(
        restored.missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
      );
      expect(
        restored.steps[0].missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
      );
      expect(restored.steps[1].missingTargetPolicy, isNull);
    });

    test('absent keys default to abortTour (old payloads)', () {
      final restored = HintTour.fromJson({
        'id': 't',
        'steps': [
          {'targetId': 'a', 'title': 'A'},
        ],
      });

      expect(
        restored.missingTargetPolicy,
        HintMissingTargetPolicy.abortTour,
      );
      expect(restored.steps.single.missingTargetPolicy, isNull);
    });

    test('old tapOnTarget/tapOnOverlay bools map to HintTapBehavior', () {
      // 0.x wire: tapOnTarget/tapOnOverlay were plain bools.
      // true ⇔ advance, false ⇔ ignore.
      final restored = HintTour.fromJson({
        'id': 't',
        'steps': [
          {
            'targetId': 'a',
            'title': 'A',
            'tapOnTarget': false,
            'tapOnOverlay': true,
          },
          {'targetId': 'b', 'title': 'B'},
        ],
      });

      expect(
        restored.steps[0].targetTap,
        isA<HintTapIgnore>(),
      );
      expect(
        restored.steps[0].overlayTap,
        isA<HintTapAdvance>(),
      );
      // Absent keys default to advance (the historical default).
      expect(
        restored.steps[1].targetTap,
        isA<HintTapAdvance>(),
      );
      expect(
        restored.steps[1].overlayTap,
        isA<HintTapAdvance>(),
      );

      // Round-trip keeps the historical bool keys (same wire shape).
      final json = restored.toJson();
      expect(json['steps'][0]['tapOnTarget'], false);
      expect(json['steps'][0]['tapOnOverlay'], true);
      expect(json['steps'][1]['tapOnTarget'], true);
      expect(json['steps'][1]['tapOnOverlay'], true);
    });

    test('resolveMissingPolicy: step overrides tour', () {
      const step = HintStep(
        targetId: 'a',
        title: 'A',
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
      );
      expect(
        step.resolveMissingPolicy(HintMissingTargetPolicy.abortTour),
        HintMissingTargetPolicy.skipStep,
      );
      const plain = HintStep(targetId: 'a', title: 'A');
      expect(
        plain.resolveMissingPolicy(HintMissingTargetPolicy.skipStep),
        HintMissingTargetPolicy.skipStep,
      );
    });
  });

  group('hintTourWithSteps', () {
    test('preserves every tour-level field (typo filtering must not drop them)',
        () {
      final tour = HintTour(
        id: 't',
        autoScroll: true,
        disableBackButton: true,
        stepTimeout: const Duration(seconds: 7),
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
        steps: const [
          HintStep(targetId: 'a', title: 'A'),
          HintStep(targetId: 'b', title: 'B'),
        ],
      );

      final filtered = hintTourWithSteps(tour, [tour.steps.first]);

      expect(filtered.id, 't');
      expect(filtered.autoScroll, isTrue);
      expect(filtered.disableBackButton, isTrue);
      expect(filtered.stepTimeout, const Duration(seconds: 7));
      expect(
        filtered.missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
      );
      expect(filtered.steps, hasLength(1));
      expect(filtered.steps.single.targetId, 'a');
    });
  });

  group('fromJson structural validation', () {
    test('empty steps throws FormatException naming the tour', () {
      expect(
        () => HintTour.fromJson({'id': 'x', 'steps': []}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('no steps'))),
      );
    });

    test('missing steps throws FormatException', () {
      expect(
        () => HintTour.fromJson({'id': 'x'}),
        throwsFormatException,
      );
    });

    test('missing id throws FormatException', () {
      expect(
        () => HintTour.fromJson({
          'steps': [
            {'targetId': 'a', 'title': 'A'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('empty id throws FormatException', () {
      expect(
        () => HintTour.fromJson({
          'id': '',
          'steps': [
            {'targetId': 'a', 'title': 'A'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('step missing targetId throws FormatException', () {
      expect(
        () => HintStep.fromJson({'title': 'T'}),
        throwsFormatException,
      );
    });

    test('step with empty targetId throws FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': '', 'title': 'T'}),
        throwsFormatException,
      );
    });

    test('a valid payload still parses', () {
      final tour = HintTour(
        id: 't',
        steps: const [HintStep(targetId: 'a', title: 'A')],
      );

      final restored = HintTour.fromJson(tour.toJson());

      expect(restored.id, 't');
      expect(restored.steps, hasLength(1));
    });
  });

  group('toJson→fromJson field round-trip', () {
    test('six never-covered fields + tour-level autoScroll survive', () {
      final tour = HintTour(
        id: 't',
        autoScroll: true,
        steps: const [
          HintStep(
            targetId: 'a',
            title: 'A',
            targetRect: Rect.fromLTWH(1, 2, 3, 4),
            focusShape: FocusShape.circle,
            focusPadding: 8,
            autoScroll: true,
            transitionDuration: Duration(milliseconds: 123),
            transitionCurve: HintCurve.sprung,
          ),
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());
      final step = restored.steps.single;

      expect(step.targetRect, const Rect.fromLTWH(1, 2, 3, 4));
      expect(step.focusShape, FocusShape.circle);
      expect(step.focusPadding, 8);
      expect(step.autoScroll, isTrue);
      expect(step.transitionDuration, const Duration(milliseconds: 123));
      expect(step.transitionCurve, HintCurve.sprung);
      expect(restored.autoScroll, isTrue);
    });
  });
}
