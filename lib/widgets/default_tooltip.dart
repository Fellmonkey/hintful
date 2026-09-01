import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/specs.dart';
import '../engine/theme/showcase_theme.dart';

/// Zero-config tooltip: title + description + Skip/Next/Done from
/// [ShowcaseTheme].
///
/// Rendered when a step has no `tooltipBuilder`. A separate widget so the
/// builder path (full customization) and the default do not duplicate theming.
/// Buttons work by mouse; plus overlay-tap and keyboard — three ways forward,
/// each self-sufficient. Buttons consume their taps (a Material button sits
/// higher in the hit-test tree than the overlay's GestureDetector); area
/// outside the buttons stays transparent for tap-on-overlay (for now a tap on
/// empty tooltip space is still next; distinguishing hits is follow-up work).
///
/// A11y minimum: the container is announced to screen readers as
/// "Step N of M: …". Text scale: the tooltip is constrained to
/// `maxWidth = min(360, screen)` — large text wraps instead of overflowing.
class DefaultTooltip extends StatelessWidget {
  const DefaultTooltip({
    super.key,
    required this.step,
    required this.ctx,
  });

  final StepSpec step;

  /// Actions + position in the tour: the same contract that `tooltipBuilder`
  /// receives ([StepTooltipContext]) — the default tooltip and a custom one
  /// do not diverge.
  final StepTooltipContext ctx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).hintTheme;
    final isLast = ctx.isLast;
    final onSurface = theme.tooltipForeground;
    final maxWidth = math
        .min(360.0, MediaQuery.sizeOf(context).width - 32)
        .clamp(160.0, 360.0);

    return Semantics(
      container: true,
      label: 'Step ${ctx.stepIndex + 1} of ${ctx.totalSteps}: '
          '${step.title ?? step.targetId}',
      child: Material(
        color: theme.tooltipBackground,
        borderRadius: theme.tooltipRadius,
        elevation: 6,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
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
                // The button row is always present: Skip is optional,
                // Next/Done is the explicit way to complete a step (the last
                // step says Done).
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (step.showSkip)
                      TextButton(
                        onPressed: ctx.actions.skip,
                        style: TextButton.styleFrom(
                          foregroundColor: onSurface,
                        ),
                        child: const Text('Skip'),
                      ),
                    if (step.showSkip) const SizedBox(width: 8),
                    // Inverted pair: the accent button contrasts with the
                    // tooltip background in any (light/dark) theme.
                    FilledButton(
                      onPressed: isLast ? ctx.actions.finish : ctx.actions.next,
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
    );
  }
}
