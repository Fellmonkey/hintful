import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/specs.dart';
import '../engine/theme/hint_theme.dart';

/// Zero-config tooltip: title + description + Skip/Back/Next/Done from
/// [HintTheme].
///
/// Rendered when a step has no `tooltipBuilder`. A separate widget so the
/// builder path (full customization) and the default do not duplicate
/// theming. Buttons work by mouse; plus overlay-tap and keyboard — three
/// ways forward, each self-sufficient. Buttons consume their taps (the
/// tooltip sits higher in the hit-test tree than the overlay's
/// GestureDetector); area outside the buttons stays transparent for
/// tap-on-overlay.
///
/// Multi-content slots ([HintStep.moreTooltips]) reuse the same widget with
/// [showActions] = false — informational tooltips without the tour controls
/// (the primary tooltip owns them) — and their own [title]/[description].
///
/// A11y: the container is announced to screen readers as "Step N of M: …";
/// each button exposes the button role + tap action.
/// Text scale: at `textScaleFactor > 1.0` the content is height-capped and
/// scrolls (the 2.0 contract: it still fits on screen). The scroll
/// machinery costs ~18 KB of heap while mounted (measured against the
/// engine baseline), so at scale 1.0 the content is only width-capped
/// (wrapping) — no scrollable is built.
class DefaultTooltip extends StatelessWidget {
  const DefaultTooltip({
    super.key,
    required this.step,
    required this.ctx,
    this.title,
    this.description,
    this.showActions = true,
  });

  final HintStep step;

  /// Content overrides for a non-primary slot: null — the step's own values.
  /// For the primary tooltip leave null (the step carries the content).
  final String? title;
  final String? description;

  /// false — an informational slot without the action button row (extra
  /// tooltips); the primary tooltip keeps its Skip/Back/Next/Done controls.
  final bool showActions;

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
    // for degenerate content. The scroll machinery is not free (~18 KB of
    // heap while mounted, measured against the engine baseline), so it is
    // mounted only when the contract needs it: at scale 1.0 the content is
    // width-capped (text wraps) and grows freely.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final maxHeight = math.max(160.0, screenSize.height - 48);
    final title = this.title ?? step.title;
    final description = this.description ?? step.description;
    // The buttons keep inheriting the ambient Material theme the way the
    // old Material buttons did (their text style was `textTheme.labelLarge`
    // — a product's fontFamily/letterSpacing/height must survive a theme
    // swap; only size/weight/color are overridden here).
    final buttonText = Theme.of(context).textTheme.labelLarge;

    // Lightweight buttons — InkWell + Text instead of Material buttons. The
    // tooltip's own Material is the ink ancestor (ripples paint on it); the
    // accent button carries its own flat Material for the inverted pair.
    // `Semantics(button: true)` keeps the button role + tap action for
    // screen readers. Measured: three Material buttons cost ~45 KB more heap
    // than this row while mounted (see benchmark/bench/
    // memory_tooltip_decomp_test.dart); the mechanics and the look are the
    // same — Skip at the far edge, small and quiet, Back/Next/Done grouped
    // at the end (the primary action is always at the very corner).
    Widget plainButton(String label, VoidCallback onPressed,
            {bool compact = false}) =>
        Semantics(
          button: true,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: compact ? 6 : 10,
              ),
              child: Text(
                label,
                style: (buttonText ?? const TextStyle(fontSize: 14)).copyWith(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w500,
                  color: onSurface,
                ),
              ),
            ),
          ),
        );

    final content = Padding(
      padding: theme.tooltipPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title,
              style: theme.tooltipTitleStyle ??
                  TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
            ),
          if (description != null) ...[
            if (title != null) const SizedBox(height: 4),
            Text(
              description,
              style: theme.tooltipDescriptionStyle ??
                  TextStyle(fontSize: 13, color: onSurface),
            ),
          ],
          // The button row. Skip is meaningless when the tour is about to
          // end anyway ("Done" does the same) — shown on intermediate steps
          // only, and only when the step opts in. This covers both a
          // single-step tour/hint and the last step of a multi-step tour.
          // Hidden for informational slots (showActions: false).
          if (showActions) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (step.showSkip && !isLast)
                  plainButton('Skip', ctx.actions.skip, compact: true),
                const Spacer(),
                if (ctx.stepIndex > 0) ...[
                  plainButton('Back', ctx.actions.previous),
                  const SizedBox(width: 8),
                ],
                // Inverted pair: the accent button contrasts with the
                // tooltip background in any (light/dark) theme.
                Semantics(
                  button: true,
                  child: Material(
                    color: onSurface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: isLast ? ctx.actions.finish : ctx.actions.next,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          isLast ? 'Done' : 'Next',
                          style: (buttonText ?? const TextStyle(fontSize: 14))
                              .copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.tooltipBackground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label: 'Step ${ctx.stepIndex + 1} of ${ctx.totalSteps}: '
          '${title ?? step.targetId}',
      child: Material(
        color: theme.tooltipBackground,
        borderRadius: theme.tooltipRadius,
        elevation: 6,
        child: textScale > 1.0
            ? ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
                child: SingleChildScrollView(child: content),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: content,
              ),
      ),
    );
  }
}