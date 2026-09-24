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

  /// The user declined (the decline is remembered in the store).
  declined,

  /// No dialog was shown: the tour already ran for this version, or the
  /// user declined this offer before (per-page or all-pages key).
  alreadyShown,

  /// The user accepted but another tour is running — nothing started;
  /// retry when [HintController.isIdle] is true.
  busy,
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
/// Two gates skip the dialog entirely (returns
/// [HintTourOfferResult.alreadyShown]): the tour itself should not show
/// ([HintStore.shouldShow] with [HintTour.minShowVersion] — it already ran
/// for this version), or the user declined before (for [pageId], or for all
/// pages when they checked the checkbox).
///
/// The store is always the controller's — [HintController.store] with the
/// session fallback from [HintController.effectiveStore]; there is no
/// per-call store. Assign `HintController(store: ...)` once for persistent
/// once-per-version semantics (otherwise the state lives for this run only).
///
/// [pageId] identifies the screen this offer belongs to (per-page decline
/// key); omitted — defaults to `tour.id` (single entry point per tour).
///
/// A decline is remembered in the store under a key separate from the tour's
/// own shown-state key, so the tour remains reachable through other entry
/// points (e.g. a settings screen). Dismissing the dialog (barrier tap)
/// counts as a decline — "not now" should not nag again. On accept the tour
/// is started via [HintController.startOnce] with [mark] (default
/// [HintMarkPolicy.onFinish]: skip/abort does not record, the tour may show
/// again — best practices §6). When the controller is busy at accept the
/// result is [HintTourOfferResult.busy] (asserts in debug).
///
/// [labels] overrides the dialog copy for this call; omitted — the design
/// system's [HintTheme.tourOfferLabels].
Future<HintTourOfferResult> showHintTourOffer({
  required BuildContext context,
  required HintController controller,
  required HintTour tour,
  String? pageId,
  HintMarkPolicy mark = HintMarkPolicy.onFinish,
  HintTourOfferLabels? labels,
}) async {
  final hintStore = controller.effectiveStore;
  final offerLabels = labels ?? Theme.of(context).hintTheme.tourOfferLabels;
  final page = pageId ?? tour.id;
  if (!hintStore.shouldShow(tour.id, minVersion: tour.minShowVersion)) {
    return HintTourOfferResult.alreadyShown; // ran for this version
  }
  if (!hintStore.shouldShow(_pageDeclineKey(tour.id, page)) ||
      !hintStore.shouldShow(_globalDeclineKey(tour.id))) {
    return HintTourOfferResult.alreadyShown; // declined before
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
    if (!controller.isIdle) {
      assert(
        false,
        'hintful: offer accepted while a tour is active — '
        'one tour at a time',
      );
      return HintTourOfferResult.busy;
    }
    // Gate already passed above (from tour.minShowVersion) — a false return
    // here means the tour was stripped as typos or busy raced in (release).
    final started = await controller.startOnce(tour, mark: mark);
    return started ? HintTourOfferResult.started : HintTourOfferResult.busy;
  }
  // Declined: remember it — per page, or for all pages when the checkbox
  // was on. The version string is arbitrary here: `shouldShow` without a
  // minVersion only asks "was it ever marked".
  hintStore.markShown(_pageDeclineKey(tour.id, page), 'true');
  if (applyToAllPages) {
    hintStore.markShown(_globalDeclineKey(tour.id), 'true');
  }
  return HintTourOfferResult.declined;
}
