import 'package:flutter/material.dart';

// The only import of the package — the public barrel: the engine internals,
// overlay machinery and machine effects are not reachable from here.
import 'package:hintful/hintful.dart';

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
/// HintTheme) and the `showHint` quick path for a single tip.
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

  ThemeMode _themeMode = ThemeMode.light;
  int _selectedFilter = 0; // 0 = all sets, 1 = by day
  bool _showStats = false; // the "Summary" card (deferred target of step 3)
  bool _statsRevealScheduled = false;

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
  }

  @override
  void dispose() {
    _controller.state.removeListener(_onTourStateChanged);
    _controller.dispose();
    super.dispose();
  }

  /// App reaction to the tour state: on step 3 we "load" the summary (a
  /// lazy-section simulation), and reset the flag on completion. Also
  /// rebuilds the AppBar icons (disabled while a tour is active).
  void _onTourStateChanged() {
    final state = _controller.currentState;
    if (state.isIdle) {
      _statsRevealScheduled = false;
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

  void _startTour() {
    if (!_controller.currentState.isIdle) return; // one tour at a time
    _controller.start(_introTour);
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
        onToggleTheme: _toggleTheme,
        onStartTour: _startTour,
        onShowHint: _showHint,
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
    required this.onToggleTheme,
    required this.onStartTour,
    required this.onShowHint,
    required this.onFilter,
  });

  final HintController controller;
  final ThemeMode themeMode;
  final int selectedFilter;
  final bool showStats;
  final List<(String, String)> entries;
  final VoidCallback onToggleTheme;
  final VoidCallback onStartTour;
  final VoidCallback onShowHint;
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
