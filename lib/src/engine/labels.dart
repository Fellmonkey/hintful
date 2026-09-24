import 'package:flutter/foundation.dart';

/// Button + announcement strings for the zero-config tooltip.
///
/// The default tooltip never hard-codes a language: it renders
/// [HintTheme.tooltipLabels] (English by default). A product localizes once,
/// in its design system — no per-screen tooltip duplication:
///
/// ```dart
/// ThemeData(
///   extensions: [
///     HintTheme.minimal(scheme).copyWith(
///       tooltipLabels: const HintTooltipLabels(
///         skip: 'Пропустить',
///         back: 'Назад',
///         next: 'Далее',
///         done: 'Готово',
///         preparing: 'Подготовка…',
///         announceStep: _announceRu, // "Шаг 1 из 3: …"
///       ),
///     ),
///   ],
/// );
/// ```
@immutable
class HintTooltipLabels {
  /// Builds labels; omitted fields keep their English defaults.
  const HintTooltipLabels({
    this.skip = 'Skip',
    this.back = 'Back',
    this.next = 'Next',
    this.done = 'Done',
    this.preparing = 'Preparing…',
    this.announceStep,
  });

  /// Action buttons of the primary tooltip.
  final String skip;

  /// "Back" button label.
  final String back;

  /// "Next" button label.
  final String next;

  /// "Done" button label (last step — replaces Next).
  final String done;

  /// Waiting-phase placeholder ("the target is not mounted yet").
  final String preparing;

  /// Screen-reader announcement per step; null — `"Step N of M: <title>"`.
  /// Gets the 0-based [stepIndex], total count and resolved title (targetId
  /// when the step has none).
  final String Function(int stepIndex, int totalSteps, String title)?
      announceStep;

  /// Announcement for a step via [announceStep] or the English default.
  String announce({
    required int stepIndex,
    required int totalSteps,
    required String title,
  }) =>
      announceStep?.call(stepIndex, totalSteps, title) ??
      'Step ${stepIndex + 1} of $totalSteps: $title';

  /// Same labels with the given fields replaced (null — keep the current).
  HintTooltipLabels copyWith({
    String? skip,
    String? back,
    String? next,
    String? done,
    String? preparing,
    String Function(int stepIndex, int totalSteps, String title)? announceStep,
  }) {
    return HintTooltipLabels(
      skip: skip ?? this.skip,
      back: back ?? this.back,
      next: next ?? this.next,
      done: done ?? this.done,
      preparing: preparing ?? this.preparing,
      announceStep: announceStep ?? this.announceStep,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HintTooltipLabels &&
      other.skip == skip &&
      other.back == back &&
      other.next == next &&
      other.done == done &&
      other.preparing == preparing &&
      other.announceStep == announceStep;

  @override
  int get hashCode =>
      Object.hash(skip, back, next, done, preparing, announceStep);
}

/// Localizable texts of the offer dialog ("Want a tour?"). All fields have
/// defaults — pass a const with overrides for a product's own wording/l10n,
/// or set `HintTheme.tourOfferLabels` once for the whole design system.
@immutable
class HintTourOfferLabels {
  /// Builds offer texts; omitted fields keep their English defaults.
  const HintTourOfferLabels({
    this.title = 'Want a tour?',
    this.body = 'Take a quick tour of what is new.',
    this.acceptLabel = 'Start',
    this.skipLabel = 'Later',
    this.applyToAllPagesLabel = 'Apply to all pages',
  });

  /// Dialog title (default — "Want a tour?").
  final String title;

  /// Dialog body text (default — "Take a quick tour of what is new.").
  final String body;

  /// Accept button label (default — "Start").
  final String acceptLabel;

  /// Decline button label (default — "Later").
  final String skipLabel;

  /// "Apply to all pages" checkbox label.
  final String applyToAllPagesLabel;

  /// Same labels with the given fields replaced (null — keep the current).
  HintTourOfferLabels copyWith({
    String? title,
    String? body,
    String? acceptLabel,
    String? skipLabel,
    String? applyToAllPagesLabel,
  }) {
    return HintTourOfferLabels(
      title: title ?? this.title,
      body: body ?? this.body,
      acceptLabel: acceptLabel ?? this.acceptLabel,
      skipLabel: skipLabel ?? this.skipLabel,
      applyToAllPagesLabel: applyToAllPagesLabel ?? this.applyToAllPagesLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HintTourOfferLabels &&
      other.title == title &&
      other.body == body &&
      other.acceptLabel == acceptLabel &&
      other.skipLabel == skipLabel &&
      other.applyToAllPagesLabel == applyToAllPagesLabel;

  @override
  int get hashCode =>
      Object.hash(title, body, acceptLabel, skipLabel, applyToAllPagesLabel);
}
