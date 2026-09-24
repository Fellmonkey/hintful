import 'package:hintful/hintful.dart';
import 'package:hintful_prefs/hintful_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's persistent [HintStore] — the ready-made `hintful_prefs`
/// implementation (namespaced keys, `clear()` dev tool).
///
/// Storage lives outside the core package on purpose: the library stays
/// dependency-free ("dart:ui + widgets only"); an app picks its own store —
/// the shipped [SharedPreferencesHintStore] here, `CallbackHintStore` over
/// its own storage, or a plain `implements HintStore`.
///
/// The store is wired app-wide once via `Hintful.configure(store: ...)` in
/// `main.dart` — `startOnce` / `showHintTourOffer` read it with no per-call
/// `store:`.
SharedPreferencesHintStore sharedPrefsHintStore(SharedPreferences prefs) =>
    SharedPreferencesHintStore(prefs);
