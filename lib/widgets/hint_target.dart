import 'package:flutter/widgets.dart';

import '../engine/registry.dart';

/// Registers a target with the engine.
///
/// A thin wrapper: registers in initState, unregisters in dispose
/// (self-cancellation by identity — disposing an old instance does not remove
/// a new owner of the same id), renders the child through
/// [CompositedTransformTarget] — the leader the overlay's follower follows
/// every frame. Zero repaints outside a tour: in idle this is one direct
/// child plus a thin leader render object.
///
/// Identification is by string id, not GlobalKey. The State creates its own
/// [LayerLink] (id is the external key, link is internal mechanics).
class HintTarget extends StatefulWidget {
  const HintTarget({
    super.key,
    required this.id,
    required this.child,
    this.registry,
    this.semanticsLabel,
  });

  /// Key in the target registry.
  final String id;

  final Widget child;

  /// Registry; defaults to [HintTargetRegistry.defaultInstance] (zero-config).
  final HintTargetRegistry? registry;

  /// Screen-reader label; null — no Semantics wrapper (a cheap option that
  /// does not touch the tree in the common case).
  final String? semanticsLabel;

  @override
  State<HintTarget> createState() => _HintTargetState();
}

class _HintTargetState extends State<HintTarget> {
  late LayerLink _link;
  late HintTargetRegistry _registry;
  late HintTargetRegistration _registration;

  @override
  void initState() {
    super.initState();
    _link = LayerLink();
    _registry = widget.registry ?? HintTargetRegistry.defaultInstance;
    _registration = _buildRegistration();
    _registry.register(_registration);
  }

  @override
  void didUpdateWidget(covariant HintTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.registry != widget.registry) {
      // "Reused key": an id change means a new target. Without re-registering,
      // the old id would linger in the registry and the tour would point at a
      // dead target (the classic dangling case). A new LayerLink is a new
      // target entity; the old one is removed by identity (not by id).
      _registry.unregister(_registration);
      _link = LayerLink();
      _registry = widget.registry ?? HintTargetRegistry.defaultInstance;
      _registration = _buildRegistration();
      _registry.register(_registration);
    }
  }

  HintTargetRegistration _buildRegistration() =>
      HintTargetRegistration(id: widget.id, link: _link, context: context);

  @override
  void dispose() {
    _registry.unregister(_registration);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = CompositedTransformTarget(link: _link, child: widget.child);
    final label = widget.semanticsLabel;
    if (label == null) return target;
    return Semantics(label: label, child: target);
  }
}
