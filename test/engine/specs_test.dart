import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hintful/src/engine/specs.dart';

void main() {
  group('missingTargetPolicy JSON round-trip (tour-level only)', () {
    test('tour policy survives toJson/fromJson; step key ignored', () {
      final tour = HintTour(
        id: 't',
        missingTargetPolicy: HintMissingTargetPolicy.skipStep,
        steps: const [
          HintStep(
            targetId: 'a',
            content: HintStepContent(title: 'A'),
          ),
          HintStep(
            targetId: 'b',
            content: HintStepContent(title: 'B'),
          ),
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());

      expect(
        restored.missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
      );
      expect(restored.steps, hasLength(2));
      // Step-level missingTargetPolicy is gone — no per-step field to read.
      final withLegacy = HintTour.fromJson({
        'id': 't',
        'missingTargetPolicy': 'skipStep',
        'steps': [
          {
            'targetId': 'a',
            'title': 'A',
            'missingTargetPolicy': 'explode-too',
          },
        ],
      });
      expect(withLegacy.missingTargetPolicy, HintMissingTargetPolicy.skipStep);
      expect(withLegacy.steps.single.content.title, 'A');
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
      expect(restored.steps.single.content.title, 'A');
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
        const HintTapBehavior.ignore(),
      );
      expect(
        restored.steps[0].overlayTap,
        const HintTapBehavior.advance(),
      );
      // Absent keys default to advance (the historical default).
      expect(
        restored.steps[1].targetTap,
        const HintTapBehavior.advance(),
      );
      expect(
        restored.steps[1].overlayTap,
        const HintTapBehavior.advance(),
      );

      // Round-trip keeps the historical bool keys (same wire shape).
      final json = restored.toJson();
      expect(json['steps'][0]['tapOnTarget'], false);
      expect(json['steps'][0]['tapOnOverlay'], true);
      expect(json['steps'][1]['tapOnTarget'], true);
      expect(json['steps'][1]['tapOnOverlay'], true);
    });

    test('resolveMissingPolicy: tour-level only (step override removed)', () {
      const step = HintStep(
        targetId: 'a',
        content: HintStepContent(title: 'A'),
      );
      // Tour-level policy is the single source — steps no longer carry one.
      expect(step.content.title, 'A');
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
        minShowVersion: '1.2.0',
        steps: const [
          HintStep(
            targetId: 'a',
            content: HintStepContent(title: 'A'),
          ),
          HintStep(
            targetId: 'b',
            content: HintStepContent(title: 'B'),
          ),
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
      expect(filtered.minShowVersion, '1.2.0');
      expect(filtered.steps, hasLength(1));
      expect(filtered.steps.single.targetId, 'a');
    });
  });

  group('minShowVersion', () {
    test('survives toJson/fromJson', () {
      final tour = HintTour(
        id: 't',
        minShowVersion: '1.2.0',
        steps: const [
          HintStep(
            targetId: 'a',
            content: HintStepContent(title: 'A'),
          )
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());

      expect(restored.minShowVersion, '1.2.0');
    });

    test('absent key stays null (old payloads)', () {
      final restored = HintTour.fromJson({
        'id': 't',
        'steps': [
          {'targetId': 'a', 'title': 'A'},
        ],
      });

      expect(restored.minShowVersion, isNull);
      expect(restored.toJson().containsKey('minShowVersion'), isFalse);
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
        steps: const [
          HintStep(
            targetId: 'a',
            content: HintStepContent(title: 'A'),
          )
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());

      expect(restored.id, 't');
      expect(restored.steps, hasLength(1));
    });
  });

  group('toJson→fromJson field round-trip', () {
    test('focus/autoScroll fields + tour-level autoScroll survive', () {
      final tour = HintTour(
        id: 't',
        autoScroll: true,
        steps: const [
          HintStep(
            targetId: 'a',
            content: HintStepContent(title: 'A'),
            focusShape: FocusShape.circle,
            focusPadding: 8,
            autoScroll: true,
          ),
        ],
      );

      final restored = HintTour.fromJson(tour.toJson());
      final step = restored.steps.single;

      expect(step.focusShape, FocusShape.circle);
      expect(step.focusPadding, 8);
      expect(step.autoScroll, isTrue);
      expect(restored.autoScroll, isTrue);
    });
  });

  group('HintTour JSON round-trip', () {
    test('toJson/fromJson preserves id, steps, timeout, disableBackButton', () {
      final tour = HintTour(
        id: 'server',
        steps: [
          HintStep(
              targetId: 'a',
              content: HintStepContent(title: 'Hello', description: 'World'),
              position: TooltipPosition.bottom),
          HintStep(
            targetId: 'b',
            content: HintStepContent(title: 'Second'),
            additionalTargets: ['c'],
            additionalTooltips: [
              HintTooltip(
                  position: TooltipPosition.top,
                  content: HintStepContent(title: 'Extra'))
            ],
            position: TooltipPosition.top,
            stepTimeout: const Duration(milliseconds: 500),
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
      expect(back.steps[0].content.title, 'Hello');
      expect(back.steps[0].position, TooltipPosition.bottom);
      expect(back.steps[1].additionalTargets, ['c']);
      expect(
          back.steps[1].additionalTooltips.first.position, TooltipPosition.top);
      expect(back.steps[1].stepTimeout, const Duration(milliseconds: 500));
      expect(back.steps[1].showSkip, false);
      expect(back.stepTimeout, const Duration(seconds: 5));
      expect(back.disableBackButton, true);
      // json string round-trip
      final s = jsonEncode(json);
      final back2 = HintTour.fromJson(jsonDecode(s) as Map<String, dynamic>);
      expect(back2.id, 'server');
    });

    test('HintTooltip toJson/fromJson', () {
      final t = HintTooltip(
          position: TooltipPosition.left,
          content: HintStepContent(title: 'T', description: 'D'));
      final back = HintTooltip.fromJson(t.toJson());
      expect(back.position, TooltipPosition.left);
      expect(back.content.title, 'T');
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
              'transitionCurve': 'wobble', // removed field → ignored, no warn
              'missingTargetPolicy': 'explode-too',
              'additionalTooltips': [
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
      // Step-level missingTargetPolicy is ignored (field removed) — no warn
      // from that key; the tour-level 'explode' still warns. Removed fields
      // (transitionCurve) are ignored silently too.
      expect(step.additionalTooltips.single.position, TooltipPosition.auto);
      expect(step.additionalTooltips.single.content.title, 'Extra');
      expect(warnings, hasLength(4));
      expect(warnings.every((w) => w.startsWith('hintful: unknown ')), isTrue);
      // The order follows argument evaluation — assert membership, not order.
      expect(warnings.any((w) => w.contains("missingTargetPolicy 'explode'")),
          isTrue);
      expect(
          warnings.any((w) => w.contains("transitionCurve 'wobble'")), isFalse);
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
      expect(warnings, isEmpty);
    });
  });
}
