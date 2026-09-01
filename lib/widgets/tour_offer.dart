import 'package:flutter/material.dart';

import '../engine/controller.dart';
import '../engine/specs.dart';
import '../engine/store.dart';

/// What happened with the "Want a tour?" pre-dialog.
enum HintTourOfferResult {
  /// The user accepted — the tour was started.
  started,

  /// No dialog was shown (the tour already ran for this version, or a
  /// previous decline) or the user declined (the decline is remembered in
  /// the store).
  declined,
}

/// Localizable texts of the offer dialog. All fields have defaults — pass a
/// const with overrides for a product's own wording/l10n.
@immutable
class HintTourOfferLabels {
  const HintTourOfferLabels({
    this.title = 'Want a tour?',
    this.body = 'Take a quick tour of what is new.',
    this.acceptLabel = 'Start',
    this.skipLabel = 'Later',
    this.applyToAllPagesLabel = 'Apply to all pages',
  });

  final String title;
  final String body;
  final String acceptLabel;
  final String skipLabel;
  final String applyToAllPagesLabel;
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
/// the tour itself should not show ([HintStore.shouldShow] with [minVersion]
/// — it already ran for this version), or the user declined before (for
/// [pageId], or for all pages when they checked the checkbox).
///
/// A decline is remembered in [store] under a key separate from the tour's
/// own shown-state key, so the tour remains reachable through other entry
/// points (e.g. a settings screen). Dismissing the dialog (barrier tap)
/// counts as a decline — "not now" should not nag again. On accept the tour
/// is started; marking its shown-state on exit stays with the app (the same
/// pattern as the versioned gate).
Future<HintTourOfferResult> showHintTourOffer({
  required BuildContext context,
  required HintController controller,
  required HintTour tour,
  required HintStore store,
  required String pageId,
  String? minVersion,
  HintTourOfferLabels labels = const HintTourOfferLabels(),
}) async {
  if (!store.shouldShow(tour.id, minVersion: minVersion)) {
    return HintTourOfferResult.declined; // already ran for this version
  }
  if (!store.shouldShow(_pageDeclineKey(tour.id, pageId)) ||
      !store.shouldShow(_globalDeclineKey(tour.id))) {
    return HintTourOfferResult.declined; // declined before
  }

  var applyToAllPages = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(labels.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(labels.body),
            CheckboxListTile(
              value: applyToAllPages,
              onChanged: (value) =>
                  setState(() => applyToAllPages = value ?? false),
              title: Text(labels.applyToAllPagesLabel),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(labels.skipLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(labels.acceptLabel),
          ),
        ],
      ),
    ),
  );

  if (accepted ?? false) {
    controller.start(tour);
    return HintTourOfferResult.started;
  }
  // Declined: remember it — per page, or for all pages when the checkbox
  // was on. The version string is arbitrary here: `shouldShow` without a
  // minVersion only asks "was it ever marked".
  store.markShown(_pageDeclineKey(tour.id, pageId), 'true');
  if (applyToAllPages) {
    store.markShown(_globalDeclineKey(tour.id), 'true');
  }
  return HintTourOfferResult.declined;
}
