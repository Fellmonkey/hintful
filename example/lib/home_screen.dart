import 'package:flutter/material.dart';

import 'package:hintful/hintful.dart';

/// Scrim/tooltip style for the visual demos — maps to [HintTheme] options
/// ([HintTheme.imageFilter] blur, [HintTheme.showPulse]). The selected style
/// applies to every tour, including the versioned intro.
enum HintStyle {
  plain('Plain'),
  blur('Blur'),
  pulse('Pulse'),
  blurPulse('Blur + Pulse');

  const HintStyle(this.label);

  final String label;
}

/// The demo home screen: registers all tour targets ('fab', 'filter-all',
/// 'filter-daily', the deferred 'stats' card and 'entry-N' workout rows) and
/// hosts the demo cards.
class HintHomeScreen extends StatelessWidget {
  const HintHomeScreen({
    super.key,
    required this.controller,
    required this.themeMode,
    required this.selectedFilter,
    required this.showStats,
    required this.entries,
    required this.appVersion,
    required this.storeReady,
    required this.introWillShow,
    required this.hintStyle,
    required this.onToggleTheme,
    required this.onStartTour,
    required this.onShowHint,
    required this.onBumpVersion,
    required this.onResetStore,
    required this.onFilter,
    required this.onStyleChanged,
    required this.onMultiTargetTour,
    required this.onMultiContentTour,
    required this.onTapRegionsTour,
    required this.onOfferTour,
  });

  final HintController controller;
  final ThemeMode themeMode;
  final int selectedFilter;
  final bool showStats;
  final List<(String, String)> entries;
  final String appVersion;
  final bool storeReady;
  final bool introWillShow;
  final HintStyle hintStyle;
  final VoidCallback onToggleTheme;
  final VoidCallback onStartTour;
  final VoidCallback onShowHint;
  final VoidCallback onBumpVersion;
  final VoidCallback onResetStore;
  final ValueChanged<int> onFilter;
  final ValueChanged<HintStyle> onStyleChanged;
  final VoidCallback onMultiTargetTour;
  final VoidCallback onMultiContentTour;
  final VoidCallback onTapRegionsTour;

  /// The offer flow needs a context UNDER the Navigator (showDialog) — the
  /// screen's own build context is passed along.
  final void Function(BuildContext context) onOfferTour;

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
          _VersionedIntroCard(
            appVersion: appVersion,
            storeReady: storeReady,
            introWillShow: introWillShow,
            onBumpVersion: onBumpVersion,
            onResetStore: onResetStore,
          ),
          const SizedBox(height: 16),
          _VisualDemosCard(
            hintStyle: hintStyle,
            tourActive: tourActive,
            onStyleChanged: onStyleChanged,
            onMultiTargetTour: onMultiTargetTour,
            onMultiContentTour: onMultiContentTour,
            onTapRegionsTour: onTapRegionsTour,
            onOfferTour: onOfferTour,
          ),
          const SizedBox(height: 24),
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

/// The versioned-intro demo: the store is app-side (shared_preferences);
/// the library ships only the contract and the in-memory default.
class _VersionedIntroCard extends StatelessWidget {
  const _VersionedIntroCard({
    required this.appVersion,
    required this.storeReady,
    required this.introWillShow,
    required this.onBumpVersion,
    required this.onResetStore,
  });

  final String appVersion;
  final bool storeReady;
  final bool introWillShow;
  final VoidCallback onBumpVersion;
  final VoidCallback onResetStore;

  @override
  Widget build(BuildContext context) {
    return Card(
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
    );
  }
}

/// One button per engine feature worth seeing with your own eyes. The scrim
/// style chips map to [HintTheme] options and apply to every tour.
class _VisualDemosCard extends StatelessWidget {
  const _VisualDemosCard({
    required this.hintStyle,
    required this.tourActive,
    required this.onStyleChanged,
    required this.onMultiTargetTour,
    required this.onMultiContentTour,
    required this.onTapRegionsTour,
    required this.onOfferTour,
  });

  final HintStyle hintStyle;
  final bool tourActive;
  final ValueChanged<HintStyle> onStyleChanged;
  final VoidCallback onMultiTargetTour;
  final VoidCallback onMultiContentTour;
  final VoidCallback onTapRegionsTour;
  final void Function(BuildContext context) onOfferTour;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Visual demos',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick a scrim style first — it applies to every tour, '
              'including the intro. Then run a tour to see the feature.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final style in HintStyle.values)
                  ChoiceChip(
                    label: Text(style.label),
                    selected: hintStyle == style,
                    onSelected: (_) => onStyleChanged(style),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: tourActive ? null : onMultiTargetTour,
                  child: const Text('Multi-target'),
                ),
                FilledButton.tonal(
                  onPressed: tourActive ? null : onMultiContentTour,
                  child: const Text('Multi-content'),
                ),
                FilledButton.tonal(
                  onPressed: tourActive ? null : onTapRegionsTour,
                  child: const Text('Tap regions'),
                ),
                FilledButton.tonal(
                  onPressed: tourActive ? null : () => onOfferTour(context),
                  child: const Text('Offer tour'),
                ),
              ],
            ),
          ],
        ),
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
