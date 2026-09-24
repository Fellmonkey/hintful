import 'package:flutter/foundation.dart' show visibleForTesting;

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
/// run through a session-scoped [InMemoryHintStore] (debug builds print a
/// one-time warning), but the state dies with the process. For a persistent
/// store use `CallbackHintStore` or the ready-made `hintful_prefs` package.
class Hintful {
  Hintful._();

  static HintStore? _store;

  /// The app-wide store, or null when none is configured (the controller then
  /// falls back to a session-scoped [InMemoryHintStore]).
  static HintStore? get store => _store;

  /// Configure the app-wide [store].
  ///
  /// Call once at startup, before the first [HintController.startOnce] /
  /// `showHintTourOffer`. Safe to call again — e.g. when async storage
  /// finishes loading after the first frames.
  static void configure({HintStore? store}) {
    _store = store;
  }

  /// Drop the configuration. A test/dev tool.
  @visibleForTesting
  static void reset() => _store = null;
}
