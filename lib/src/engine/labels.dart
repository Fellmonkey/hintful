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
  final String back;
  final String next;
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
