import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';

import '../engine/controller.dart';
import '../engine/labels.dart';
import '../engine/specs.dart';
import '../engine/store.dart';
import '../engine/theme/hint_theme.dart';

/// What happened with the "Want a tour?" pre-dialog.
///
/// Closed in 1.x: no new values will be added before 2.0. Exhaustive
/// `switch`es over this enum in app code are safe; genuinely new outcomes
/// arrive as new API, not a new value.
enum HintTourOfferResult {
  /// The user accepted — the tour was started.
  started,

  /// No dialog was shown (the tour already ran for this version, or a
  /// previous decline) or the user declined (the decline is remembered in
  /// the store).
  declined,
}

/// The offer's decline keys are namespaced apart from the tour's own
/// shown-state key ([HintStore] entries keyed by `tour.id`): declining an
/// offer must not suppress the tour from other entry points.
const String _declinePrefix = 'offer:';

String _pageDeclineKey(String tourId, String pageId) =>
    '$_declinePrefix$tourId@$pageId';

String _globalDeclineKey(String tourId) => '$_declinePrefix$tourId';

/// Show the pre-tour offer dialog — "Want a tour?" with an
/// "Apply to all pages" checkbox — and start [tour] on accept.
///
/// Two gates skip the dialog entirely (returns [HintTourOfferResult.declined]):
/// the tour itself should not show ([HintStore.shouldShow] with
/// [HintTour.minShowVersion] — it already ran for this version), or the user
/// declined before (for [pageId], or for all pages when they checked the
/// checkbox).
///
/// The store is [store] when given, else `controller.store` — set
/// `HintController(store: ...)` once and omit `store:` here. With no store
/// anywhere the offer still shows, but **nothing persists**: the version
/// gate and both decline keys are skipped, a decline is forgotten, and an
/// accept records nothing (a debug print says so) — pass a store for the
/// documented ask-once behavior.
///
/// [pageId] identifies the screen this offer belongs to (per-page decline
/// key); omitted — defaults to `tour.id` (single entry point per tour).
///
/// A decline is remembered in the store under a key separate from the tour's
/// own shown-state key, so the tour remains reachable through other entry
/// points (e.g. a settings screen). Dismissing the dialog (barrier tap)
/// counts as a decline — "not now" should not nag again. On accept the tour
/// is started and (with [markOnFinish], the default) the shown-state is
/// recorded **on finish** via [HintController.startOnce] — skip/abort does
/// not record, the tour may show again (best practices §6). Pass
/// `markOnFinish: false` to record the shown-state yourself (any other
/// policy — see best practices §6).
///
/// [labels] overrides the dialog copy for this call; omitted — the design
/// system's [HintTheme.tourOfferLabels].
Future<HintTourOfferResult> showHintTourOffer({
  required BuildContext context,
  required HintController controller,
  required HintTour tour,
  HintStore? store,
  String? pageId,
  bool markOnFinish = true,
  HintTourOfferLabels? labels,
}) async {
  final hintStore = store ?? controller.store;
  if (kDebugMode && hintStore == null) {
    debugPrint(
      'hintful: showHintTourOffer without a HintStore — the version gate, '
      'declines and the shown-state are not persisted (set '
      'HintController.store or pass store:)',
    );
  }
  final offerLabels = labels ?? Theme.of(context).hintTheme.tourOfferLabels;
  final page = pageId ?? tour.id;
  if (hintStore != null) {
    if (!hintStore.shouldShow(tour.id, minVersion: tour.minShowVersion)) {
      return HintTourOfferResult.declined; // already ran for this version
    }
    if (!hintStore.shouldShow(_pageDeclineKey(tour.id, page)) ||
        !hintStore.shouldShow(_globalDeclineKey(tour.id))) {
      return HintTourOfferResult.declined; // declined before
    }
  }

  var applyToAllPages = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(offerLabels.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(offerLabels.body),
            CheckboxListTile(
              value: applyToAllPages,
              onChanged: (value) =>
                  setState(() => applyToAllPages = value ?? false),
              title: Text(offerLabels.applyToAllPagesLabel),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(offerLabels.skipLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(offerLabels.acceptLabel),
          ),
        ],
      ),
    ),
  );

  if (accepted ?? false) {
    if (markOnFinish && hintStore != null) {
      // startOnce: gate (already passed above, from tour.minShowVersion)
      // + start + markShown on finish only; skip/abort leaves the tour
      // re-showable (§6). The gate above already ran, so a false return
      // here means busy.
      assert(
        controller.isIdle,
        'hintful: offer accepted while a tour is active — '
        'one tour at a time',
      );
      final started = await controller.startOnce(tour, store: hintStore);
      return started
          ? HintTourOfferResult.started
          : HintTourOfferResult.declined;
    }
    // No store (nothing to record) or markOnFinish: false — start without
    // recording; the app marks the shown-state itself if it has a policy
    // (best practices §6 listener pattern).
    // Awaited: start() validates synchronously (typo assert) and must not
    // fail into an unhandled async error after we already reported success.
    await controller.start(tour);
    return HintTourOfferResult.started;
  }
  // Declined: remember it — per page, or for all pages when the checkbox
  // was on. The version string is arbitrary here: `shouldShow` without a
  // minVersion only asks "was it ever marked".
  hintStore?.markShown(_pageDeclineKey(tour.id, page), 'true');
  if (applyToAllPages) {
    hintStore?.markShown(_globalDeclineKey(tour.id), 'true');
  }
  return HintTourOfferResult.declined;
}
