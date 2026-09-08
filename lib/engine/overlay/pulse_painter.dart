import 'package:flutter/widgets.dart';

import '../position_resolver.dart';
import '../specs.dart' show FocusShape;

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
  PulsePainter({
    required this.animation,
    required this.resolver,
    required this.color,
    this.focusShape = FocusShape.rectangle,
    this.focusPadding = 4.0,
  });

  final Animation<double>? animation;
  final HintPositionResolver? resolver;
  final Color color;
  final FocusShape focusShape;
  final double focusPadding;

  @override
  void paint(Canvas canvas, Size size) {
    final position = resolver?.resolve();
    if (position is! PositionedHint) return;
    final hole = (Offset.zero & position.size).inflate(focusPadding).shift(position.translation);
    final t = (animation?.value ?? 0).clamp(0.0, 1.0);
    final expansion = 24 * t;
    final ringRect = hole.inflate(expansion);
    final opacity = t < 0.5 ? 1.0 : 1.0 - (t - 0.5) * 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withAlpha((opacity * 255).round());
    switch (focusShape) {
      case FocusShape.circle:
        final side = ringRect.width > ringRect.height
            ? ringRect.width
            : ringRect.height;
        canvas.drawOval(
            Rect.fromCenter(center: ringRect.center, width: side, height: side),
            paint);
      case FocusShape.roundedRect:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                ringRect, const Radius.circular(12)),
            paint);
      case FocusShape.rectangle:
        canvas.drawRRect(
            RRect.fromRectAndRadius(ringRect, const Radius.circular(4)),
            paint);
    }
  }

  @override
  bool shouldRepaint(covariant PulsePainter oldDelegate) =>
      !identical(oldDelegate.animation, animation) ||
      !identical(oldDelegate.resolver, resolver) ||
      oldDelegate.color != color;

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
