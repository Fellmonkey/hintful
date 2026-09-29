import 'package:flutter/foundation.dart' show internal, visibleForTesting;

import 'store.dart';

/// App-wide configuration for the zero-config path.
///
/// One call at startup wires the versioned-hints store every controller reads,
/// so `store:` never has to be threaded through constructors:
///
/// ```dart
/// Hintful.configure(store: await loadMyStore());
/// final controller = HintController();
/// ```
///
/// The store is optional: without one, show-once still works for the current
/// run through one app-wide session-scoped [InMemoryHintStore] (a one-time
/// warning is printed on first fallback, in debug and release alike), but the
/// state dies with the process. For a persistent store use `CallbackHintStore`
/// or the ready-made `hintful_prefs` package.
class Hintful {
  Hintful._();

  static HintStore? _store;

  /// The app-wide session fallback, created on first use by the controller's
  /// `store` getter. **App-wide by design**: "session-scoped" means one store
  /// per app run, not one per controller — a hint marked shown by one
  /// controller must stay shown for every other controller in the same run
  /// (the natural failure it prevents: two controllers on one screen each
  /// keeping their own shown-state, show-once double-firing). Lazily created
  /// so an app that always configures a persistent store allocates nothing.
  static InMemoryHintStore? _sessionStore;

  /// The shared session fallback; lazily created. `@internal`: the
  /// controller's `store` getter is the only caller; not part of the barrel.
  @internal
  static InMemoryHintStore get sessionStore =>
      _sessionStore ??= InMemoryHintStore();

  /// The app-wide store, or null when none is configured (the controller then
  /// falls back to the shared session-scoped [InMemoryHintStore]).
  static HintStore? get store => _store;

  /// Configure the app-wide [store].
  ///
  /// Call once at startup, before the first [HintController.startOnce] /
  /// `showHintTourOffer`. Safe to call again — e.g. when async storage
  /// finishes loading after the first frames.
  static void configure({HintStore? store}) {
    _store = store;
  }

  /// Drop the configuration, including the shared session fallback — a fresh
  /// run (or test) must not inherit the previous one's shown-state.
  @visibleForTesting
  static void reset() {
    _store = null;
    _sessionStore = null;
  }
}
