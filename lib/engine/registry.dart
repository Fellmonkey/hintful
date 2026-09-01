import 'package:flutter/widgets.dart';

/// An immutable snapshot of a registered target.
///
/// [id] — string key (not a GlobalKey), [link] — the CompositedTransform
/// mechanics (follows the target every frame), [context] — for position
/// snapshots on step changes and root-overlay capture.
///
/// Hard rule: the context may only be read while handling a step-change
/// event and is never stored by the overlay — it must not be used after
/// dispose.
@immutable
class TargetRegistration {
  const TargetRegistration({
    required this.id,
    required this.link,
    required this.context,
  });

  final String id;
  final LayerLink link;
  final BuildContext context;
}

/// Target registry by string ids — the heart of the "no GlobalKey" model.
///
/// Policies:
///
/// - **Duplicate id: "last registration wins"** + warning. ListView rebuilds
///   create a new target instance on every layout, so "first registered"
///   quickly goes stale.
/// - **Unregister by identity, not by id**: [unregister] takes the
///   registration object itself and only removes it if it is the current
///   owner of the id. Disposing an old instance cannot remove a fresh one —
///   this architecturally rules out the classic bug "dispose of the old one
///   killed the new one".
/// - **Data only**: the registry stores no widgets/elements — just id, link
///   and context; no leaks.
class TargetRegistry {
  TargetRegistry({this.onWarning});

  /// Global instance for zero-config (`ShowcaseTarget` without `registry:`).
  /// Tests and apps with their own registries create separate instances.
  static final TargetRegistry defaultInstance = TargetRegistry();

  /// Developer warnings (duplicate id etc.); in debug builds the controller
  /// wires up printing.
  void Function(String warning)? onWarning;

  final Set<VoidCallback> _listeners = {};

  /// Subscribe to registry changes (registration or removal of the current
  /// owner). The controller subscribes here and translates changes into
  /// state-machine events (appeared/vanished); other subsystems can
  /// subscribe the same way. Re-subscribing the same callback is a no-op.
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Unsubscribe; removing an unsubscribed callback is a silent no-op
  /// (dispose races are inevitable, not an error).
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  final Map<String, TargetRegistration> _byId = {};

  /// Current registration for [id], or null if the target is not mounted.
  TargetRegistration? lookup(String id) => _byId[id];

  /// All registered ids (unmodifiable copy; used for typo candidates).
  Set<String> get ids => Set.unmodifiable(_byId.keys);

  void register(TargetRegistration registration) {
    final existing = _byId[registration.id];
    if (existing != null && !identical(existing, registration)) {
      onWarning?.call(
        "hintful: duplicate target id '${registration.id}'"
        ' — newest registration wins',
      );
    }
    _byId[registration.id] = registration;
    _notifyChanged();
  }

  /// Removes [registration] only if it is the current owner of its id.
  /// A foreign/stale registration is a silent no-op (dispose races are
  /// inevitable) and does not notify listeners.
  void unregister(TargetRegistration registration) {
    final owner = _byId[registration.id];
    if (owner == null || !identical(owner, registration)) {
      return;
    }
    _byId.remove(registration.id);
    _notifyChanged();
  }

  void _notifyChanged() {
    // Copy: a listener may unsubscribe/resubscribe during notification.
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}
