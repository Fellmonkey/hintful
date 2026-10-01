import 'package:flutter/widgets.dart';

import '../position_resolver.dart';
import '../specs.dart' show FocusShape, kHintFocusPadding, kHintHoleRadius;
import 'scrim_painter.dart';

/// Pulsing ring around the primary target (Material feature-discovery
/// pattern). Opt-in via `HintTheme.showPulse`; the animation runs only while
/// a step is active with the flag on.
///
/// The painter lives in the **global overlay layer** (full-screen canvas),
/// painted ABOVE the scrim — including the blur scrim, which is a global
/// `BackdropFilter` layer of its own (a pulse inside the target's follower
/// would end up under the blur). The ring is anchored at the resolver's
/// global translation, so it follows the target while the picture repaints
/// (the animation tick repaints every frame, reading the compositor
/// transform live — no rebuilds, no extra lag).
class PulsePainter extends CustomPainter {
  /// Creates a painter for one repaint configuration.
  PulsePainter({
    required this.animation,
    required this.resolver,
    required this.color,
    this.focusShape = FocusShape.rectangle,
    this.focusPadding = kHintFocusPadding,
    this.holeRadius = kHintHoleRadius,
  });

  /// Pulse progress animation (0..1). Null — the ring is drawn at phase 0
  /// (static, fully opaque) instead of being skipped; pass a running
  /// controller for the actual pulse.
  final Animation<double>? animation;

  /// Source of the target's position (null — nothing to ring).
  final HintPositionResolver? resolver;

  /// Ring stroke color (usually the theme accent).
  final Color color;

  /// Shape of the ring — matches the scrim hole.
  final FocusShape focusShape;

  /// Padding from the target bounds — the ring starts at the hole edge.
  final double focusPadding;

  /// Corner radius of a rounded-rect ring - the same knob the scrim hole
  /// uses, so ring and hole always read as one shape.
  final double holeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final position = resolver?.resolve();
    if (position == null) return;
    // The ring geometry has exactly one source: the pure [pulseRing] helper
    // (unit-tested directly) — the paint path must not re-derive it. Its
    // `size` is the hole's, and the phase is clamped inside the helper.
    final hole = (Offset.zero & position.size)
        .inflate(focusPadding)
        .shift(position.translation);
    final (localRing, opacity) = pulseRing(animation?.value ?? 0, hole.size);
    final ringRect = localRing.shift(hole.topLeft);
    // One shape table for the package: the ring strokes exactly the path the
    // scrim punches (stroked, so corners read as the hole's corners — a
    // stroked rect is sharp, a circle round (longer-side diameter), a rounded
    // rect clamped
    // the same way as the scrim's).
    final path =
        RectScrimPainter.holeShape(ringRect, focusShape, radius: holeRadius);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withAlpha((opacity * 255).round()),
    );
  }

  @override
  bool shouldRepaint(covariant PulsePainter oldDelegate) =>
      !identical(oldDelegate.animation, animation) ||
      !identical(oldDelegate.resolver, resolver) ||
      oldDelegate.color != color ||
      oldDelegate.focusShape != focusShape ||
      oldDelegate.focusPadding != focusPadding ||
      oldDelegate.holeRadius != holeRadius;

  /// The expanding ring for a pulse [phase] in 0..1 around a hole of [size]:
  /// `(rect, opacity)`. The rect inflates from the hole by up to [expansion]
  /// (in each direction); the opacity holds for the first half of the phase
  /// and fades linearly to zero by the end. Pure — unit-tested directly.
  static (Rect, double) pulseRing(
    double phase,
    Size size, {
    double expansion = 24,
  }) {
    final t = phase.clamp(0.0, 1.0);
    final rect = (Offset.zero & size).inflate(t * expansion);
    final opacity = t < 0.5 ? 1.0 : 1.0 - (t - 0.5) * 2;
    return (rect, opacity);
  }
}
