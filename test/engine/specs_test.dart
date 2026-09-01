import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/engine/specs.dart';

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
}
