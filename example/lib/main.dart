import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The only import of the package — the public barrel: the engine internals,
// overlay machinery and machine effects are not reachable from here.
import 'package:hintful/hintful.dart';

import 'demo_tours.dart';
import 'home_screen.dart';
import 'shared_prefs_hint_store.dart';

void main() => runApp(const ExampleApp());

/// Demonstrates hintful end to end:
///
/// 1. **Target following**: the tooltip and the scrim hole are tied to the
///    target by a compositor transform — they ride along with any movement /
///    re-layout (proven by tests: `position_resolver_test` and a tour-level
///    test with a programmatic scroll). The scrim is transparent to drags
///    (scroll-through — the page scrolls under an active tour) and owns
///    taps, split into target/overlay regions with tap positions.
/// 2. **Zero idle cost**: until a tour starts, the tree only holds thin
///    leader wrappers of the targets — no overlay widgets at all.
/// 3. **Deferred target**: the intro tour's step 3 waits for the "Summary"
///    card to appear — the section "loads" 600 ms after the step activates
///    (wait-for-target, timeout with diagnostics — the same mechanism as
///    for lazy tabs).
///
/// The screen and the tours live in their own files: [HintHomeScreen]
/// (target registration + demo cards) and `demo_tours.dart` (tour
/// definitions). This file is the shell — the controller, the
/// versioned-intro store gate, the light/dark + scrim-style theming and the
/// app reactions to tour state (per tour id — e.g. only the intro reveals
/// the deferred summary card).
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  // Zero-config: the default registry + an engine that captures the root
  // overlay of the first mounted target by itself. The host is built lazily —
  // only on the first non-idle state, absent while idle. defaultOverlayHost()
  // is the single public entry into render mechanics.
  final HintController _controller = HintController(
    overlayHostBuilder: defaultOverlayHost(),
  );

  /// The versioned-hints store; null until `shared_preferences` loads
  /// (async init) — the demo card shows "Loading…" and the versioned gate
  /// is inert until it is ready.
  HintStore? _store;

  /// The demo's pretend app version — bumped by the "Bump version" button
  /// to demonstrate the "new in this version" re-show.
  String _appVersion = '1.0.0';

  /// Set when a versioned entry point starts its tour (the AppBar intro and
  /// the "Offer tour" demo); on the next idle (finish/skip/timeout) it is
  /// marked shown for the current app version — no nagging in the same
  /// version.
  String? _activeTourId;

  ThemeMode _themeMode = ThemeMode.light;
  int _selectedFilter = 0; // 0 = all sets, 1 = by day
  bool _showStats = false; // the "Summary" card (deferred target of step 3)
  bool _statsRevealScheduled = false;
  HintStyle _hintStyle = HintStyle.plain;

  // The State's own context is ABOVE MaterialApp (no ScaffoldMessenger
  // ancestor) — snackbars go through the app's messenger key instead.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static const _entries = <(String, String)>[
    ('Bench press', '80 kg × 5'),
    ('Squats', '100 kg × 8'),
    ('Deadlift', '120 kg × 5'),
    ('Pull-ups', '10 × 3'),
    ('Push-ups', '25 × 4'),
    ('Lunges', '30 kg × 10'),
  ];

  @override
  void initState() {
    super.initState();
    _controller.state.addListener(_onTourStateChanged);
    // The app-side store: `shared_preferences` is async, the library core
    // stays dependency-free (see shared_prefs_hint_store.dart).
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _store = SharedPrefsHintStore(prefs));
    });
  }

  @override
  void dispose() {
    _controller.state.removeListener(_onTourStateChanged);
    _controller.dispose();
    super.dispose();
  }

  /// App reaction to the tour state, gated by tour id: only the intro tour
  /// "loads" the summary on step 3 (lazy-section simulation) and only the
  /// versioned intro is marked shown on exit. Also rebuilds the AppBar
  /// icons (disabled while a tour is active).
  void _onTourStateChanged() {
    final state = _controller.currentState;
    if (state.isIdle) {
      _statsRevealScheduled = false;
      final active = _activeTourId;
      if (active != null) {
        _activeTourId = null;
        // Finished, skipped or timed out — the user has seen it; do not
        // nag again in this version.
        _store?.markShown(active, _appVersion);
      }
      if (mounted) setState(() {});
      return;
    }
    if (state.tour?.id == 'intro' &&
        state.stepIndex == 2 &&
        !_statsRevealScheduled) {
      _statsRevealScheduled = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showStats = true);
      });
    }
    if (mounted) setState(() {});
  }

  /// The versioned-intro entry: show once per app version. Gated — when the
  /// intro already showed in [_appVersion], explain instead of showing
  /// ("Bump version" re-enables it).
  void _startTour() {
    if (!_controller.currentState.isIdle) return; // one tour at a time
    final store = _store;
    if (store == null) return; // prefs not loaded yet
    if (!store.shouldShow('intro', minVersion: _appVersion)) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'The intro already showed in $_appVersion — '
            'bump the version to see it again.',
          ),
        ),
      );
      return;
    }
    _activeTourId = 'intro';
    _controller.start(introTour());
  }

  /// Demo controls: 1.0.0 → 1.1.0 → … — "new in this version" re-shows the
  /// intro.
  void _bumpVersion() {
    setState(() {
      final parts = _appVersion.split('.').map(int.parse).toList();
      parts[2] += 1;
      _appVersion = parts.join('.');
    });
    if (_store?.shouldShow('intro', minVersion: _appVersion) ?? false) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('New version — the intro is available again.'),
        ),
      );
    }
  }

  /// Demo control: hard-reset the store (the production "re-show" is a
  /// version bump; this is the debug/dev tool).
  void _resetStore() {
    setState(() => _store?.clear()); // refresh the demo card's status
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Store cleared — the intro will show again.'),
      ),
    );
  }

  /// Quick path for a single tip: a one-step tour without the HintTour
  /// ceremony.
  void _showHint() {
    if (!_controller.currentState.isIdle) return;
    _controller.showHint(
      const HintStep(
        targetId: 'fab',
        title: 'This is the quick-log button',
        description: 'One tip — no tour, no configuration.',
      ),
    );
  }

  void _startMultiTargetTour() =>
      _guardStart(() => _controller.start(multiTargetTour()));

  void _startMultiContentTour() =>
      _guardStart(() => _controller.start(multiContentTour()));

  void _startTapRegionsTour() =>
      _guardStart(() => _controller.start(tapRegionsTour(_notify)));

  /// The pre-tour offer: "Want a tour?" with an "Apply to all pages"
  /// checkbox; the decision (start or decline) is persisted via the store —
  /// per page, or globally when the checkbox is on. The tour itself is built
  /// from an enum ([HintTour.fromEnum]) — see demo_tours.dart.
  void _startOfferTour(BuildContext context) {
    if (!_controller.currentState.isIdle) return; // one tour at a time
    final store = _store;
    if (store == null) return; // prefs not loaded yet
    showHintTourOffer(
      context: context,
      controller: _controller,
      tour: offerTour(),
      store: store,
      pageId: 'HomePage',
      minVersion: _appVersion,
    ).then((result) {
      if (result == HintTourOfferResult.started) {
        _activeTourId = 'offer'; // marked shown on exit — no re-offer
      }
    });
  }

  void _guardStart(VoidCallback start) {
    if (_controller.currentState.isIdle) start();
  }

  /// Snackbar channel for tour callbacks (tap-region demo) — the shell owns
  /// the messenger key. A fresh notification replaces the previous one
  /// (channel semantics, not a queue).
  void _notify(String message) {
    final messenger = _messengerKey.currentState;
    messenger?.clearSnackBars();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleTheme() => setState(() => _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  void _onStyleChanged(HintStyle style) => setState(() => _hintStyle = style);

  /// Hint theming as part of the design system: the product describes it via
  /// a ThemeExtension, the engine picks it up automatically. The minimal()
  /// default is a ColorScheme inverseSurface pair; the selected demo style
  /// maps to the blur ([HintTheme.imageFilter]) and pulse ([HintTheme.showPulse])
  /// options.
  HintTheme _hintTheme(ColorScheme scheme) {
    final theme = HintTheme.minimal(scheme).copyWith(
      tooltipRadius: BorderRadius.circular(16),
      tooltipPadding: const EdgeInsets.all(20),
    );
    return switch (_hintStyle) {
      HintStyle.plain => theme,
      HintStyle.blur => theme.copyWith(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          scrimColor: Colors.black.withAlpha(90), // blur dims too
        ),
      HintStyle.pulse => theme.copyWith(showPulse: true),
      HintStyle.blurPulse => theme.copyWith(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          scrimColor: Colors.black.withAlpha(90),
          showPulse: true,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Hintful demo',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: lightScheme,
        extensions: [_hintTheme(lightScheme)],
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        extensions: [_hintTheme(darkScheme)],
      ),
      themeMode: _themeMode,
      home: HintHomeScreen(
        controller: _controller,
        themeMode: _themeMode,
        selectedFilter: _selectedFilter,
        showStats: _showStats,
        entries: _entries,
        appVersion: _appVersion,
        storeReady: _store != null,
        introWillShow:
            _store?.shouldShow('intro', minVersion: _appVersion) ?? false,
        hintStyle: _hintStyle,
        onToggleTheme: _toggleTheme,
        onStartTour: _startTour,
        onShowHint: _showHint,
        onBumpVersion: _bumpVersion,
        onResetStore: _resetStore,
        onFilter: (index) => setState(() {
          _selectedFilter = index;
          _showStats = index == 1;
        }),
        onStyleChanged: _onStyleChanged,
        onMultiTargetTour: _startMultiTargetTour,
        onMultiContentTour: _startMultiContentTour,
        onTapRegionsTour: _startTapRegionsTour,
        onOfferTour: _startOfferTour,
      ),
    );
  }
}
