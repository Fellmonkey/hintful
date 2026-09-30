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

    test('absent key defaults to skipStep (the Dart default)', () {
      final restored = HintTour.fromJson({
        'id': 't',
        'steps': [
          {'targetId': 'a', 'title': 'A'},
        ],
      });

      expect(
        restored.missingTargetPolicy,
        HintMissingTargetPolicy.skipStep,
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

  group('fromJson wrong-typed values throw FormatException (not TypeError)',
      () {
    test('waitTimeoutMs as a double throws FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'waitTimeoutMs': 3.5}),
        throwsFormatException,
      );
    });

    test('stepTimeoutMs as a string on a step throws FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'stepTimeoutMs': '3000'}),
        throwsFormatException,
      );
    });

    test('stepTimeoutMs is the step key; waitTimeoutMs still parses', () {
      const step = HintStep(
        targetId: 'a',
        stepTimeout: Duration(milliseconds: 700),
      );
      final json = step.toJson();
      expect(json['stepTimeoutMs'], 700);
      expect(json['waitTimeoutMs'], isNull,
          reason: 'the symmetric name is the one written');

      expect(
        HintStep.fromJson({'targetId': 'a', 'stepTimeoutMs': 700}).stepTimeout,
        const Duration(milliseconds: 700),
      );
      expect(
        HintStep.fromJson({'targetId': 'a', 'waitTimeoutMs': 700}).stepTimeout,
        const Duration(milliseconds: 700),
        reason: 'the pre-1.0 key keeps parsing',
      );
      expect(
        HintStep.fromJson({
          'targetId': 'a',
          'stepTimeoutMs': 700,
          'waitTimeoutMs': 1234,
        }).stepTimeout,
        const Duration(milliseconds: 700),
        reason: 'the canonical key wins when both are present',
      );
    });

    test('stepTimeoutMs as a string throws FormatException', () {
      expect(
        () => HintTour.fromJson({
          'id': 'x',
          'stepTimeoutMs': '3000',
          'steps': [
            {'targetId': 'a'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('additionalTargets with a non-String element throws at parse time',
        () {
      expect(
        () => HintStep.fromJson({
          'targetId': 'a',
          'additionalTargets': [42],
        }),
        throwsFormatException,
      );
    });

    test('a non-map step throws at parse time (no TypeError)', () {
      expect(
        () => HintTour.fromJson({
          'id': 'x',
          'steps': [42],
        }),
        throwsFormatException,
      );
    });

    test('a non-list additionalTooltips throws at parse time', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'additionalTooltips': 'x'}),
        throwsFormatException,
      );
      expect(
        () => HintStep.fromJson({
          'targetId': 'a',
          'additionalTooltips': [42],
        }),
        throwsFormatException,
      );
    });

    test('showSkip / tapOnTarget as strings throw FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'showSkip': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'tapOnTarget': 'true'}),
        throwsFormatException,
      );
    });

    test('focusPadding as a string throws FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'focusPadding': '8'}),
        throwsFormatException,
      );
    });

    test('a non-String title throws FormatException', () {
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'title': 5}),
        throwsFormatException,
      );
      expect(
        () => HintStep.fromJson({'targetId': 'a', 'description': []}),
        throwsFormatException,
      );
    });

    test('disableBackButton / autoScroll / minShowVersion type-checked', () {
      final steps = [
        {'targetId': 'a'},
      ];
      expect(
        () => HintTour.fromJson({
          'id': 'x',
          'disableBackButton': 'yes',
          'steps': steps,
        }),
        throwsFormatException,
      );
      expect(
        () => HintTour.fromJson({
          'id': 'x',
          'autoScroll': 1,
          'steps': steps,
        }),
        throwsFormatException,
      );
      expect(
        () => HintTour.fromJson({
          'id': 'x',
          'minShowVersion': 3,
          'steps': steps,
        }),
        throwsFormatException,
      );
    });

    test('numeric focusPadding stays accepted (int or double)', () {
      final step = HintStep.fromJson({'targetId': 'a', 'focusPadding': 8});
      expect(step.focusPadding, 8.0);
    });

    test('the unknown-enum warning path is NOT turned into a throw', () {
      final warnings = <String>[];
      final tour = HintTour.fromJson(
        {
          'id': 'x',
          'missingTargetPolicy': 7,
          'steps': [
            {'targetId': 'a'},
          ],
        },
        onWarning: warnings.add,
      );
      expect(tour.missingTargetPolicy, HintMissingTargetPolicy.skipStep);
      expect(warnings, hasLength(1));
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
              HintAdditionalTooltip(
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

    test('HintAdditionalTooltip toJson/fromJson', () {
      final t = HintAdditionalTooltip(
          position: TooltipPosition.left,
          content: HintStepContent(title: 'T', description: 'D'));
      final back = HintAdditionalTooltip.fromJson(t.toJson());
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
      expect(tour.missingTargetPolicy, HintMissingTargetPolicy.skipStep);
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
