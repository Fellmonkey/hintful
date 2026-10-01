import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// A target's position for rendering the scrim/tooltip: its top-left corner
/// in overlay coordinates plus its size.
///
/// A resolver returns `null` instead when the target has no position (not in
/// the tree yet/already) — there is nothing to point at.
@immutable
class PositionedHint {
  /// Creates a positioned hint from overlay-space [translation] + [size].
  const PositionedHint({required this.translation, required this.size});

  /// Offset of the target's top-left corner in overlay coordinates (the
  /// space where the CompositedTransformFollower wrapper lives).
  final Offset translation;

  /// Target size (`LayerLink.leaderSize`).
  final Size size;

  @override
  String toString() => 'PositionedHint($translation, $size)';
}

/// Source of target positions.
///
/// The abstraction exists so the engine does not depend directly on Flutter's
/// internal layer APIs: if `FollowerLayer.getLastTransform()` breaks or gets
/// renamed, one implementation is fixed instead of the whole overlay.
abstract class HintPositionResolver {
  /// Current position of the target, or null when it has none.
  PositionedHint? resolve();
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
  /// Captures the follower render object read on every [resolve].
  CompositorHintResolver(this._follower);

  final RenderFollowerLayer _follower;

  @override
  PositionedHint? resolve() {
    final leaderSize = _follower.link.leaderSize;
    final transform = _follower.layer?.getLastTransform();
    if (leaderSize == null || transform == null) {
      return null;
    }
    assert(
        _isAxisAlignedOrUniformScale(transform),
        'non-axis-aligned (rotated / non-uniformly scaled) transform: '
        '${transform.storage}');
    // A **uniform** ancestor scale is representable as an axis-aligned rect:
    // the compositor's translation is the leader origin in follower space, and
    // the leader's local size scales with it. Rotation/shear and non-uniform
    // scale have no axis-aligned representation and are rejected above (debug
    // assert): in release they would otherwise be silently misplaced.
    final scale = transform.storage[0];
    return PositionedHint(
      translation: Offset(transform.storage[12], transform.storage[13]),
      size: scale == 1.0
          ? leaderSize
          : Size(leaderSize.width * scale, leaderSize.height * scale),
    );
  }

  /// A leader is axis-aligned under a **uniform** scale (no rotation/shear,
  /// `s[0] == s[5] > 0`): a uniformly scaled ancestor (`Transform.scale`,
  /// `FittedBox`) stays an axis-aligned rectangle, so it is accepted and its
  /// size is scaled in [resolve]. Non-uniform scale and rotation have no
  /// axis-aligned representation and are rejected.
  ///
  /// Comparison uses an epsilon, not `==`: the compositor multiplies ancestor
  /// matrices and ortho-components pick up numerical noise ~1e-16 (found while
  /// exercising the example app's FAB).
  static bool _isAxisAlignedOrUniformScale(Matrix4 matrix) {
    const epsilon = 1e-6;
    final s = matrix.storage;
    final sx = s[0];
    final sy = s[5];
    return sx > epsilon &&
        (sx - sy).abs() < epsilon &&
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
