import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Target position for rendering the scrim/tooltip.
///
/// [PositionedHint] — the target is mounted and the compositor knows its
/// position; [UnpositionedHint] — the target is not in the tree (yet/already),
/// there is no position.
@immutable
sealed class HintPosition {
  const HintPosition();
}

@immutable
class PositionedHint extends HintPosition {
  const PositionedHint({required this.translation, required this.size});

  /// Offset of the target's top-left corner in overlay coordinates (the
  /// space where the CompositedTransformFollower wrapper lives).
  final Offset translation;

  /// Target size (`LayerLink.leaderSize`).
  final Size size;

  @override
  String toString() => 'PositionedHint($translation, $size)';
}

@immutable
class UnpositionedHint extends HintPosition {
  const UnpositionedHint();

  @override
  String toString() => 'UnpositionedHint()';
}

/// Source of target positions.
///
/// The abstraction exists so the engine does not depend directly on Flutter's
/// internal layer APIs: if `FollowerLayer.getLastTransform()` breaks or gets
/// renamed, one implementation is fixed instead of the whole overlay.
abstract class HintPositionResolver {
  HintPosition resolve();
}

/// A resolver that never yields a position: used in waiting mode when the
/// target does not exist yet and the scrim is drawn fully (no hole).
class UnpositionedHintResolver implements HintPositionResolver {
  const UnpositionedHintResolver();

  @override
  HintPosition resolve() => const UnpositionedHint();
}

/// Target position **from the compositor** — the engine's main resolver.
///
/// Mechanics (verified against Flutter 3.47):
/// - `FollowerLayer.getLastTransform()` (layer.dart:2707) stores the leader
///   transform, recomputed every frame by the compositor at addToScene —
///   scroll/re-layout/animations update the position with zero manual
///   measuring from Dart;
/// - `LayerLink.leaderSize` (proxy_box.dart:4510) is written by the leader
///   on every layout of the target.
///
/// The object captures a [RenderFollowerLayer] (the render object of
/// CompositedTransformFollower) once at construction and reads the layer on
/// each `resolve()`. The source is the follower itself, not `link.leader`:
/// `LeaderLayer` has no `getLastTransform` method.
class CompositorHintResolver implements HintPositionResolver {
  CompositorHintResolver(this._follower);

  final RenderFollowerLayer _follower;

  @override
  HintPosition resolve() {
    final size = _follower.link.leaderSize;
    final transform = _follower.layer?.getLastTransform();
    if (size == null || transform == null) {
      return const UnpositionedHint();
    }
    assert(
        _isAxisAligned(transform),
        'non-axis-aligned transform: '
        '${transform.storage}');
    return PositionedHint(
      translation: Offset(transform.storage[12], transform.storage[13]),
      size: size,
    );
  }

  /// A leader is always axis-aligned (the engine does not rotate/scale
  /// targets); translation is taken from storage[12..13], so we verify that
  /// there is no rotation/scale — otherwise the coordinates would be wrong.
  ///
  /// Comparison uses an epsilon, not `== 0.0`: the compositor multiplies
  /// ancestor matrices and ortho-components pick up numerical noise ~1e-16
  /// (found while exercising the example app's FAB).
  static bool _isAxisAligned(Matrix4 matrix) {
    const epsilon = 1e-6;
    final s = matrix.storage;
    return (s[0] - 1.0).abs() < epsilon &&
        (s[5] - 1.0).abs() < epsilon &&
        (s[10] - 1.0).abs() < epsilon &&
        s[1].abs() < epsilon &&
        s[2].abs() < epsilon &&
        s[3].abs() < epsilon &&
        s[4].abs() < epsilon &&
        s[6].abs() < epsilon &&
        s[7].abs() < epsilon &&
        s[8].abs() < epsilon &&
        s[9].abs() < epsilon &&
        s[11].abs() < epsilon;
  }
}
