import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The only import of the package — the public barrel: the engine internals,
// overlay machinery and machine effects are not reachable from here.
import 'package:hintful/hintful.dart';

import 'shared_prefs_hint_store.dart';

void main() => runApp(const ExampleApp());

/// Demonstrates hintful end to end:
///
/// 1. **Target following**: the tooltip and the scrim hole are tied to the
///    target by a compositor transform — they ride along with any movement /
///    re-layout (proven by tests: `position_resolver_test` and a tour-level
///    test with a programmatic scroll). For now the scrim blocks interaction
///    with the app during the tour (a single "tap = next"); scroll-through
///    is follow-up work.
/// 2. **Zero idle cost**: until a tour starts, the tree only holds thin
///    leader wrappers of the targets — no overlay widgets at all.
/// 3. **Deferred target**: step 3 waits for the "Summary" card to appear —
///    the section "loads" 600 ms after the step activates (wait-for-target,
///    timeout with diagnostics — the same mechanism as for lazy tabs).
///
/// Plus: light/dark (hint theming inherits the ColorScheme through
/// HintTheme), the `showHint` quick path for a single tip, smart
/// positioning (tooltip tail, keep-in-safe-area) and the versioned-intro
/// pattern (N4): the intro tour shows once per app version — `shouldShow`
/// before start, `markShown` on exit, a version bump re-shows it (demo
/// buttons "Bump version" / "Reset store"). The store is a
/// `shared_preferences`-backed `HintStore` living in the app — the library
/// core stays dependency-free.
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

  /// Set when the versioned intro starts; on the next idle (finish/skip/
  /// timeout) it is marked shown for the current version — no nagging in
  /// the same version.
  bool _introStarted = false;

  ThemeMode _themeMode = ThemeMode.light;
  int _selectedFilter = 0; // 0 = all sets, 1 = by day
  bool _showStats = false; // the "Summary" card (deferred target of step 3)
  bool _statsRevealScheduled = false;

  // The State's own context is ABOVE MaterialApp (no ScaffoldMessenger
  // ancestor) — snackbars from the versioned-intro actions go through the
  // app's messenger key instead.
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

  /// App reaction to the tour state: on step 3 we "load" the summary (a
  /// lazy-section simulation), and reset the flag on completion. When the
  /// versioned intro exits (any way), it is marked shown for the current
  /// app version. Also rebuilds the AppBar icons (disabled while a tour is
  /// active).
  void _onTourStateChanged() {
    final state = _controller.currentState;
    if (state.isIdle) {
      _statsRevealScheduled = false;
      if (_introStarted) {
        _introStarted = false;
        // Finished, skipped or timed out — the user has seen it; do not
        // nag again in this version.
        _store?.markShown('intro', _appVersion);
      }
      if (mounted) setState(() {});
      return;
    }
    if (state.stepIndex == 2 && !_statsRevealScheduled) {
      _statsRevealScheduled = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showStats = true);
      });
    }
    if (mounted) setState(() {});
  }

  HintTour get _introTour => HintTour(
        id: 'intro',
        steps: [
          HintStep(
            targetId: 'fab',
            title: 'Quick log',
            description: 'Add sets with one tap. '
                'Next we show the day filter.',
          ),
          HintStep(
            targetId: 'filter-daily',
            title: 'Daily filter',
            description: 'The day summary — the next tour step.',
          ),
          HintStep(
            targetId: 'stats',
            title: 'Summary card',
            description: 'It appeared automatically — that is '
                'wait-for-target for deferred sections.',
          ),
          HintStep(
            targetId: 'entry-0',
            title: 'Workout list',
            description: 'Every entry is a target too. Done!',
          ),
        ],
      );

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
    _introStarted = true;
    _controller.start(_introTour);
  }

  /// Demo control: 1.0.0 → 1.1.0 → … — "new in this version" re-shows the
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

  void _toggleTheme() => setState(() => _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  /// Hint theming as part of the design system: the product describes it via
  /// a ThemeExtension, the engine picks it up automatically. The minimal()
  /// default is a ColorScheme inverseSurface pair; here — a light tweak.
  HintTheme _hintTheme(ColorScheme scheme) =>
      HintTheme.minimal(scheme).copyWith(
        tooltipRadius: BorderRadius.circular(16),
        tooltipPadding: const EdgeInsets.all(20),
      );

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
      home: _HomeScreen(
        controller: _controller,
        themeMode: _themeMode,
        selectedFilter: _selectedFilter,
        showStats: _showStats,
        entries: _entries,
        appVersion: _appVersion,
        storeReady: _store != null,
        introWillShow:
            _store?.shouldShow('intro', minVersion: _appVersion) ?? false,
        onToggleTheme: _toggleTheme,
        onStartTour: _startTour,
        onShowHint: _showHint,
        onBumpVersion: _bumpVersion,
        onResetStore: _resetStore,
        onFilter: (index) => setState(() {
          _selectedFilter = index;
          _showStats = index == 1;
        }),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.controller,
    required this.themeMode,
    required this.selectedFilter,
    required this.showStats,
    required this.entries,
    required this.appVersion,
    required this.storeReady,
    required this.introWillShow,
    required this.onToggleTheme,
    required this.onStartTour,
    required this.onShowHint,
    required this.onBumpVersion,
    required this.onResetStore,
    required this.onFilter,
  });

  final HintController controller;
  final ThemeMode themeMode;
  final int selectedFilter;
  final bool showStats;
  final List<(String, String)> entries;
  final String appVersion;
  final bool storeReady;
  final bool introWillShow;
  final VoidCallback onToggleTheme;
  final VoidCallback onStartTour;
  final VoidCallback onShowHint;
  final VoidCallback onBumpVersion;
  final VoidCallback onResetStore;
  final ValueChanged<int> onFilter;

  @override
  Widget build(BuildContext context) {
    final tourActive = !controller.currentState.isIdle;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hintful'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              themeMode == ThemeMode.light
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
            ),
            onPressed: onToggleTheme,
          ),
          IconButton(
            tooltip: 'Show hint',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: tourActive ? null : onShowHint,
          ),
          IconButton(
            tooltip: 'Show tour',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: tourActive ? null : onStartTour,
          ),
        ],
      ),
      floatingActionButton: HintTarget(
        id: 'fab',
        child: FloatingActionButton.extended(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Set added (demo)')),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Log a set'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Versioned-intro demo (N4): the store is app-side
          // (shared_preferences); the library ships only the contract and
          // the in-memory default.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Versioned intro',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    storeReady
                        ? 'App version $appVersion — the intro '
                            '${introWillShow ? 'will show again' : 'already showed in this version'}'
                        : 'Loading the store…',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: storeReady ? onBumpVersion : null,
                        child: const Text('Bump version'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: storeReady ? onResetStore : null,
                        child: const Text('Reset store'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              HintTarget(
                id: 'filter-all',
                child: ChoiceChip(
                  label: const Text('All sets'),
                  selected: selectedFilter == 0,
                  onSelected: (_) => onFilter(0),
                ),
              ),
              const SizedBox(width: 8),
              HintTarget(
                id: 'filter-daily',
                child: ChoiceChip(
                  label: const Text('By day'),
                  selected: selectedFilter == 1,
                  onSelected: (_) => onFilter(1),
                ),
              ),
            ],
          ),
          if (showStats) ...[
            const SizedBox(height: 24),
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            HintTarget(
              id: 'stats',
              child: const _StatsCard(),
            ),
          ],
          const SizedBox(height: 24),
          Text('Workouts', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < entries.length; i++)
            HintTarget(
              // Every entry is a target: the registry survives ListView
              // rebuilds (last-wins + identity guard).
              id: 'entry-$i',
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
                title: Text(entries[i].$1),
                subtitle: Text(entries[i].$2),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(label: 'Sets', value: '42', style: style),
            _Stat(label: 'Volume', value: '12.4 t', style: style),
            _Stat(label: 'Days', value: '18', style: style),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: style),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
