import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/specs.dart';
import '../engine/theme/hint_theme.dart';

/// Zero-config tooltip: title + description + Skip/Next/Done from
/// [HintTheme].
///
/// Rendered when a step has no `tooltipBuilder`. A separate widget so the
/// builder path (full customization) and the default do not duplicate theming.
/// Buttons work by mouse; plus overlay-tap and keyboard — three ways forward,
/// each self-sufficient. Buttons consume their taps (a Material button sits
/// higher in the hit-test tree than the overlay's GestureDetector); area
/// outside the buttons stays transparent for tap-on-overlay (for now a tap on
/// empty tooltip space is still next; distinguishing hits is follow-up work).
///
/// A11y: the container is announced to screen readers as "Step N of M: …".
/// Text scale: the tooltip is constrained to `maxWidth = min(360, screen)`
/// and a height cap — at `textScaleFactor = 2.0` the content wraps and
/// scrolls instead of overflowing the screen.
class DefaultTooltip extends StatelessWidget {
  const DefaultTooltip({
    super.key,
    required this.step,
    required this.ctx,
  });

  final HintStep step;

  /// Actions + position in the tour: the same contract that `tooltipBuilder`
  /// receives ([HintTooltipContext]) — the default tooltip and a custom one
  /// do not diverge.
  final HintTooltipContext ctx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).hintTheme;
    final isLast = ctx.isLast;
    final onSurface = theme.tooltipForeground;
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.min(360.0, screenSize.width - 32).clamp(160.0, 360.0);
    // Text-scale contract: at `textScaleFactor = 2.0` the tooltip still fits
    // on screen — the height is capped and the content scrolls instead of
    // overflowing (long text wraps within maxWidth and grows vertically until
    // the cap). The cap also keeps the placement fallback corner on screen
    // for degenerate content.
    final maxHeight = math.max(160.0, screenSize.height - 48);

    return Semantics(
      container: true,
      label: 'Step ${ctx.stepIndex + 1} of ${ctx.totalSteps}: '
          '${step.title ?? step.targetId}',
      child: Material(
        color: theme.tooltipBackground,
        borderRadius: theme.tooltipRadius,
        elevation: 6,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Padding(
              padding: theme.tooltipPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step.title != null)
                    Text(
                      step.title!,
                      style: theme.tooltipTitleStyle ??
                          TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                    ),
                  if (step.description != null) ...[
                    if (step.title != null) const SizedBox(height: 4),
                    Text(
                      step.description!,
                      style: theme.tooltipDescriptionStyle ??
                          TextStyle(fontSize: 13, color: onSurface),
                    ),
                  ],
                  // The button row: Skip sits at the far edge, small and
                  // quiet — a tap aimed at the primary action must not hit
                  // it. Back and Next/Done are grouped at the end (the
                  // primary action is always at the very corner).
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (step.showSkip)
                        TextButton(
                          onPressed: ctx.actions.skip,
                          style: TextButton.styleFrom(
                            foregroundColor: onSurface,
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: const Text('Skip'),
                        ),
                      const Spacer(),
                      if (ctx.stepIndex > 0) ...[
                        TextButton(
                          onPressed: ctx.actions.previous,
                          style: TextButton.styleFrom(
                            foregroundColor: onSurface,
                          ),
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Inverted pair: the accent button contrasts with the
                      // tooltip background in any (light/dark) theme.
                      FilledButton(
                        onPressed:
                            isLast ? ctx.actions.finish : ctx.actions.next,
                        style: FilledButton.styleFrom(
                          backgroundColor: onSurface,
                          foregroundColor: theme.tooltipBackground,
                        ),
                        child: Text(isLast ? 'Done' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
