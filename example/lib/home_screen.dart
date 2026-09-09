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
    required this.onCircleHoleTour,
    required this.onRoundedHoleTour,
    required this.onNegativePaddingTour,
    required this.onRectTargetTour,
    required this.onSprungTour,
    required this.onHooksTour,
    required this.onFadeSlideTour,
    required this.onJsonTour,
    required this.onL10nTour,
    required this.onAutoScrollStepTour,
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
  final VoidCallback onCircleHoleTour;
  final VoidCallback onRoundedHoleTour;
  final VoidCallback onNegativePaddingTour;
  final VoidCallback onRectTargetTour;
  final VoidCallback onSprungTour;
  final VoidCallback onHooksTour;
  final VoidCallback onFadeSlideTour;
  final VoidCallback onJsonTour;
  final void Function(BuildContext) onL10nTour;
  final VoidCallback onAutoScrollStepTour;

  /// The offer flow needs a context UNDER the Navigator (showDialog) - the
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
          _VisualDemosCard(
            hintStyle: hintStyle,
            tourActive: tourActive,
            onStyleChanged: onStyleChanged,
            onMultiTargetTour: onMultiTargetTour,
            onMultiContentTour: onMultiContentTour,
            onTapRegionsTour: onTapRegionsTour,
            onOfferTour: onOfferTour,
            onCircleHoleTour: onCircleHoleTour,
            onRoundedHoleTour: onRoundedHoleTour,
            onNegativePaddingTour: onNegativePaddingTour,
            onRectTargetTour: onRectTargetTour,
            onSprungTour: onSprungTour,
            onHooksTour: onHooksTour,
            onFadeSlideTour: onFadeSlideTour,
            onJsonTour: onJsonTour,
            onL10nTour: onL10nTour,
            onAutoScrollStepTour: onAutoScrollStepTour,
          ),
          const SizedBox(height: 24),
          Text('Filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('All sets'),
                selected: selectedFilter == 0,
                onSelected: (_) => onFilter(0),
              ).withHint('filter-all'),
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
              focusShape: i == 5 ? FocusShape.circle : null,
              focusPadding: i == 5 ? 6 : null,
              child: ListTile(
                // entry-8 demonstrates withHint as alternative syntax:
                // `CircleAvatar(...).withHint('entry-8')` would also work.
                leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
                title: Text(entries[i].$1),
                subtitle: Text(entries[i].$2),
              ),
            ),
          // Version tooling lives at the bottom: it re-triggers the intro
          // for version-flow testing, but it is not the demo's focus.
          const SizedBox(height: 24),
          _VersionedIntroCard(
            appVersion: appVersion,
            storeReady: storeReady,
            introWillShow: introWillShow,
            onBumpVersion: onBumpVersion,
            onResetStore: onResetStore,
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
    required this.onCircleHoleTour,
    required this.onRoundedHoleTour,
    required this.onNegativePaddingTour,
    required this.onRectTargetTour,
    required this.onSprungTour,
    required this.onHooksTour,
    required this.onFadeSlideTour,
    required this.onJsonTour,
    required this.onL10nTour,
    required this.onAutoScrollStepTour,
  });

  final HintStyle hintStyle;
  final bool tourActive;
  final ValueChanged<HintStyle> onStyleChanged;
  final VoidCallback onMultiTargetTour;
  final VoidCallback onMultiContentTour;
  final VoidCallback onTapRegionsTour;
  final VoidCallback onCircleHoleTour;
  final VoidCallback onRoundedHoleTour;
  final VoidCallback onNegativePaddingTour;
  final VoidCallback onRectTargetTour;
  final VoidCallback onSprungTour;
  final VoidCallback onHooksTour;
  final VoidCallback onFadeSlideTour;
  final VoidCallback onJsonTour;
  final void Function(BuildContext) onL10nTour;
  final VoidCallback onAutoScrollStepTour;
  final void Function(BuildContext context) onOfferTour;

  /// One demo button: disabled while a tour runs (starting a second tour
  /// mid-tour is a contract violation, not a feature).
  Widget _tourButton(String label, VoidCallback onPressed) {
    return FilledButton.tonal(
      onPressed: tourActive ? null : onPressed,
      child: Text(label),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }

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
            const SizedBox(height: 16),
            _sectionLabel(context, 'Tours & content'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('New here? Start with these — then shapes below.'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tourButton('Multi-target', onMultiTargetTour),
                _tourButton('Multi-content', onMultiContentTour),
                _tourButton('Tap regions', onTapRegionsTour),
                _tourButton('Offer tour', () => onOfferTour(context)),
                _tourButton('JSON', onJsonTour),
                _tourButton('L10n', () => onL10nTour(context)),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Spotlight shapes'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tourButton('Circle', onCircleHoleTour),
                _tourButton('Rounded', onRoundedHoleTour),
                _tourButton('Neg pad', onNegativePaddingTour),
                _tourButton('Rect', onRectTargetTour),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Motion & logic'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tourButton('Sprung', onSprungTour),
                _tourButton('Custom', onFadeSlideTour),
                _tourButton('Hooks', onHooksTour),
                _tourButton('Step scroll', onAutoScrollStepTour),
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






