import 'package:flutter/material.dart';

import '../engine/controller.dart';
import '../engine/labels.dart';
import '../engine/specs.dart';
import '../engine/store.dart';
import '../engine/theme/hint_theme.dart';

/// What happened with the "Want a tour?" pre-dialog.
///
/// Six outcomes, one per reason the dialog did or did not lead to a tour —
/// the caller can tell "the version gate is closed" from "the user already
/// said no" from "I was too busy" without reading the store itself.
///
/// Closed in 1.x: no new values will be added before 2.0. Exhaustive
/// `switch`es over this enum in app code are safe; genuinely new outcomes
/// arrive as new API, not a new value.
enum HintTourOfferResult {
  /// The user accepted — the tour was shown.
  shown,

  /// The user declined this offer (the decline is remembered in the store).
  declined,

  /// No dialog: [HintStore.shouldShow] is false for the tour's own key with
  /// [HintTour.minShowVersion] — it already ran for this version.
  versionGated,

  /// No dialog: the user declined this offer before (per-page or all-pages
  /// key). The tour itself is still reachable from other entry points.
  previouslyDeclined,

  /// The user accepted but another tour was running (retry when
  /// [HintController.isIdle] is true). Asserts in debug.
  busy,

  /// The user accepted, nothing else was in the way, but there was nothing
  /// to show: every step was stripped as a typo, or the tour is empty.
  ///
  /// Reachable in release — debug builds fail loudly on the empty/typo tour
  /// before this point ([HintController.showTour]'s asserts), so a test
  /// cannot land here.
  nothingToShow,
}

/// The offer's decline keys are namespaced apart from the tour's own
/// shown-state key ([HintStore] entries keyed by `tour.id`): declining an
/// offer must not suppress the tour from other entry points.
const String _declinePrefix = 'offer:';

String _pageDeclineKey(String tourId, String pageId) =>
    '$_declinePrefix$tourId@$pageId';

String _globalDeclineKey(String tourId) => '$_declinePrefix$tourId';

/// Show the pre-tour offer dialog — "Want a tour?" with an
/// "Apply to all pages" checkbox — and show [tour] on accept.
///
/// Two gates skip the dialog entirely: the tour already ran for this version
/// ([HintTourOfferResult.versionGated]), or the user declined this offer
/// before — for [pageId], or for all pages when they checked the checkbox
/// ([HintTourOfferResult.previouslyDeclined]).
///
/// The store is app-wide — `Hintful.configure(store: ...)` once at startup;
/// there is no per-call store. Without one the state lives for this run only
/// (a session fallback).
///
/// [pageId] identifies the screen this offer belongs to (per-page decline
/// key); omitted — defaults to `tour.id` (single entry point per tour).
///
/// A decline is remembered in the store under a key separate from the tour's
/// own shown-state key, so the tour remains reachable through other entry
/// points (e.g. a settings screen). Dismissing the dialog (barrier tap)
/// counts as a decline — "not now" should not nag again. On accept the tour
/// is started via [HintController.tryShowTour] with [mark] (default
/// [HintMarkPolicy.onAnyExit]: finish, skip and abort all count as "seen" —
/// best practices §6); that call is the single atomic gate, so a controller
/// busy at accept yields [HintTourOfferResult.busy] (asserts in debug) and
/// an unshowable tour yields [HintTourOfferResult.nothingToShow].
///
/// [labels] overrides the dialog copy for this call; omitted — the design
/// system's [HintTheme.tourOfferLabels].
Future<HintTourOfferResult> showHintTourOffer({
  required BuildContext context,
  required HintController controller,
  required HintTour tour,
  String? pageId,
  HintMarkPolicy mark = HintMarkPolicy.onAnyExit,
  HintTourOfferLabels? labels,
}) async {
  final hintStore = controller.store;
  final offerLabels = labels ?? Theme.of(context).hintTheme.tourOfferLabels;
  final page = pageId ?? tour.id;
  if (!hintStore.shouldShow(tour.id, minVersion: tour.minShowVersion)) {
    return HintTourOfferResult.versionGated; // ran for this version
  }
  if (!hintStore.shouldShow(_pageDeclineKey(tour.id, page)) ||
      !hintStore.shouldShow(_globalDeclineKey(tour.id))) {
    return HintTourOfferResult.previouslyDeclined; // declined before
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
    // tryShowTour is the one gate that matters: it checks the store and the
    // busy flag atomically, so there is no second check-then-act here — the
    // classification below only reads what that call already decided.
    final shown = await controller.tryShowTour(tour, mark: mark);
    if (shown) return HintTourOfferResult.shown;
    if (!controller.isIdle) {
      // The accept raced another tour starting — one tour at a time.
      assert(
        false,
        'hintful: offer accepted while a tour is active — '
        'one tour at a time',
      );
      return HintTourOfferResult.busy;
    }
    if (!hintStore.shouldShow(tour.id, minVersion: tour.minShowVersion)) {
      return HintTourOfferResult.versionGated; // raced with another marker
    }
    return HintTourOfferResult.nothingToShow;
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
