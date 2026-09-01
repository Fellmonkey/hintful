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
