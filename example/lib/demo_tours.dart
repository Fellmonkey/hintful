import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hintful/hintful.dart';

/// All demo tours of the example app, in one place.
///
/// Every tour targets ids registered by the home screen ([HintHomeScreen]):
/// 'fab', 'filter-all', 'filter-daily', 'stats' (deferred) and 'entry-N'.

/// The classic tour: quick log → daily filter → deferred summary → workout
/// entry. Demonstrates wait-for-target on step 3 (the "Summary" card mounts
/// 600 ms after the step activates), scroll-into-view for list targets and
/// the versioned-intro pattern: shown once per app version via the store
/// gate in the app shell.
HintTour introTour() => HintTour(
      id: 'intro',
      steps: [
        HintStep(
          targetId: 'fab',
          title: 'Quick log',
          description: 'Add sets with one tap. '
              'Next we show the day filter.',
        ),
        HintStep(
          targetId: 'filter-daily',
          title: 'Daily filter',
          description: 'The day summary — the next tour step.',
        ),
        HintStep(
          targetId: 'stats',
          title: 'Summary card',
          description: 'It appeared automatically — that is '
              'wait-for-target for deferred sections.',
        ),
        HintStep(
          targetId: 'entry-0',
          title: 'Workout list',
          description: 'Every entry is a target too. Done!',
        ),
      ],
    );

/// Multi-target: one step spotlighting two elements at once — each gets its
/// own scrim hole and the tooltip never covers either of them — followed by
/// a single-target step for contrast.
HintTour multiTargetTour() => HintTour(
      id: 'multi-target',
      steps: [
        HintStep(
          targetId: 'filter-all',
          moreTargets: ['filter-daily'],
          title: 'Both filters at once',
          description: 'One step can spotlight several targets — '
              'each has its own scrim hole, the tooltip avoids them all.',
        ),
        HintStep(
          targetId: 'fab',
          title: 'Back to one target',
          description: 'This step spotlights a single target — '
              'contrast it with the previous one.',
        ),
      ],
    );

/// Multi-content: several tooltips around one target. The primary tooltip
/// owns the controls; the extra slots are informational and never overlap
/// each other or the target.
HintTour multiContentTour() => HintTour(
      id: 'multi-content',
      steps: [
        HintStep(
          targetId: 'fab',
          title: 'Primary tooltip',
          description: 'The primary tooltip — it owns the tour controls.',
          moreTooltips: [
            HintTooltip(
              position: TooltipPosition.left,
              title: 'Left slot',
              description: 'An extra tooltip on the left — '
                  'informational, no buttons.',
            ),
            HintTooltip(
              position: TooltipPosition.top,
              title: 'Top slot',
              description: 'Another slot on top. Slots never overlap '
                  'each other or the spotlighted target.',
            ),
          ],
        ),
      ],
    );

/// Tap regions: a tap on a spotlighted target vs a tap on the scrim fire
/// different callbacks (with the tap position); per-step you can also turn
/// a region off entirely.
HintTour tapRegionsTour(void Function(String message) notify) => HintTour(
      id: 'tap-regions',
      steps: [
        HintStep(
          targetId: 'fab',
          title: 'Tap target vs overlay',
          description: 'Tap the button (target) or the dark area '
              '(overlay) — each fires its own callback with the tap '
              'position. Use Next to advance.',
          onTapTarget: (ctx, details) => notify(
            'Target tap at '
            '${details.localPosition.dx.round()},'
            '${details.localPosition.dy.round()}',
          ),
          onTapOverlay: (ctx, details) =>
              notify('Overlay tap — advance with Next'),
        ),
        HintStep(
          targetId: 'entry-0',
          title: 'Overlay taps off',
          description: 'This step ignores overlay taps '
              '(tapOnOverlay: false) — only a target tap or the button '
              'advances.',
          tapOnOverlay: false,
        ),
      ],
    );

/// The steps of the offer tour as an enum: the values (in declaration
/// order) ARE the step list — see [offerTour].
enum OfferStep { fab, filters }

/// A tour built from an enum ([HintTour.fromEnum]): the exhaustive switch in
/// `stepFor` is checked at compile time — adding or removing an [OfferStep]
/// value breaks the build, so the tour can never silently drift from the
/// enum. Used by the "Offer tour" demo, which first asks "Want a tour?"
/// (see `showHintTourOffer`).
HintTour offerTour() => HintTour.fromEnum(
      id: 'offer',
      values: OfferStep.values,
      stepFor: (step) => switch (step) {
        OfferStep.fab => HintStep(
            targetId: 'fab',
            title: 'Quick log',
            description: 'A tour built from an enum — the switch here is '
                'exhaustive, so the steps can never drift from the enum.',
          ),
        OfferStep.filters => HintStep(
            targetId: 'filter-all',
            title: 'All sets filter',
            description: 'Declared order of the enum = order of the steps.',
          ),
      },
    );

/// New 51-feature demos — Visual demos card.

HintTour circleHoleTour() => HintTour(
      id: 'feat-circle',
      steps: [HintStep(targetId: 'fab', title: 'Circle hole', focusShape: FocusShape.circle)],
    );

HintTour roundedHoleTour() => HintTour(
      id: 'feat-rounded',
      steps: [HintStep(targetId: 'filter-all', title: 'Rounded hole', focusShape: FocusShape.roundedRect)],
    );

HintTour negativePaddingTour() => HintTour(
      id: 'feat-neg-pad',
      steps: [HintStep(targetId: 'fab', title: 'Shrink', description: 'focusPadding -8', focusPadding: -8)],
    );

HintTour rectTargetTour() => HintTour(
      id: 'feat-rect',
      steps: [
        HintStep(
          targetId: 'fab',
          targetRect: const Rect.fromLTWH(100, 300, 120, 40),
          title: 'Rect by coords',
          description: 'targetRect — without HintTarget (test)',
        ),
      ],
    );

HintTour sprungTour() => HintTour(
      id: 'feat-sprung',
      steps: [HintStep(targetId: 'fab', title: 'Sprung', description: 'Sprung curve — bouncy', transitionCurve: HintCurve.sprung, transitionDuration: const Duration(milliseconds: 350))],
    );

HintTour hooksTour(void Function(String m) notify) => HintTour(
      id: 'feat-hooks',
      steps: [
        HintStep(
          targetId: 'fab',
          title: 'Hooks',
          description: 'onBefore/onAfter - prepare scene',
          onBeforeAction: () async => notify('before hook'),
          onAfterAction: () async => notify('after hook'),
        ),
      ],
    );

/// Rung 3 of the animation ladder: a fully custom entry (fade + rise)
/// through `tooltipBuilder` — the engine places whatever the builder
/// returns (positioning, tail side, safe area all still apply), the builder
/// owns how it enters, down to its own action button. Honors reduce-motion
/// by rendering instantly.
HintTour fadeSlideTour() => HintTour(
      id: 'feat-fade-slide',
      steps: [
        HintStep(
          targetId: 'fab',
          title: 'Fade and rise',
          description: 'Custom entry, custom button.',
          tooltipBuilder: (context, step, ctx) {
            final theme = Theme.of(context).hintTheme;
            final reduceMotion =
                MediaQuery.maybeOf(context)?.disableAnimations ?? false;
            final card = Semantics(
              container: true,
              label: step.title,
              child: Material(
                color: theme.tooltipBackground,
                borderRadius: theme.tooltipRadius,
                elevation: 6,
                child: Padding(
                  padding: theme.tooltipPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title ?? '', style: theme.tooltipTitleStyle),
                      if (step.description != null) ...[
                        const SizedBox(height: 4),
                        Text(step.description!,
                            style: theme.tooltipDescriptionStyle),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: ctx.actions.finish,
                          child: const Text('Got it'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (reduceMotion) return card;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - t)),
                  child: child,
                ),
              ),
              child: card,
            );
          },
        ),
      ],
    );

/// Server-driven shape without a server: the exact JSON a backend would
/// serve, parsed by `HintTour.fromJson` — proves the wire format end to end
/// (titles, descriptions, positions, timeouts all survive the round trip).
HintTour jsonTour() => HintTour.fromJson(
      jsonDecode(_jsonTourDocument) as Map<String, dynamic>,
    );

const _jsonTourDocument = '''
{"id":"feat-json","stepTimeoutMs":3000,"steps":[
{"targetId":"fab","title":"From JSON","description":"This step rode in as JSON, not Dart.","position":"auto"},
{"targetId":"filter-all","title":"Second from JSON","description":"Multi-step tours serialize too.","position":"auto"}
]}''';
