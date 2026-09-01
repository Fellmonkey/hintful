import 'package:flutter/widgets.dart';

import '../position_resolver.dart';

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
  });

  /// The repeating phase in 0..1; null — a static ring at phase 0 (not used
  /// in practice: the engine starts the controller only when pulsing).
  final Animation<double>? animation;

  /// The primary target's resolver (hole size at paint time).
  final HintPositionResolver? resolver;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final position = resolver?.resolve();
    if (position is! PositionedHint) return; // nothing to pulse around
    final (ring, opacity) = pulseRing(animation?.value ?? 0, position.size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      // withAlpha (not deprecated across the supported 3.10+ range; the
      // theme uses the same convention).
      ..color = color.withAlpha((opacity * 255).round());
    // The ring is computed relative to the hole (see [pulseRing]); in the
    // global layer the canvas origin is the screen corner — shift by the
    // target's global translation.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        ring.shift(position.translation),
        const Radius.circular(12),
      ),
      paint,
    );
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
