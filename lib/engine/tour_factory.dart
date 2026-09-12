import 'dart:convert';

import 'specs.dart';

/// Factory for server-driven tours — `HintTour` from JSON.
///
/// `HintTour.fromJson/toJson` is the wire format
/// `{id, steps:[{targetId,title,position}], stepTimeoutMs}`.
/// No `http` dependency in `hintful` — bring your own fetcher (http,
/// dio, `HttpClient`, `package:http`, etc.).
abstract class HintTourFactory {
  Future<HintTour> fetch(String id);
}

/// In-memory factory — tests, previews, local tours.
class InMemoryHintTourFactory implements HintTourFactory {
  InMemoryHintTourFactory(this._tours);
  final Map<String, HintTour> _tours;
  @override
  Future<HintTour> fetch(String id) async {
    final t = _tours[id];
    if (t == null) throw StateError('tour $id not found');
    return t;
  }
}

/// Network factory — you provide `fetcher` (e.g. `(uri) => http.get(uri).then((r)=>r.body)`).
class FetcherHintTourFactory implements HintTourFactory {
  FetcherHintTourFactory({
    required this.baseUrl,
    required this.fetcher,
    this.onWarning,
  });

  final String baseUrl;
  final Future<String> Function(Uri uri) fetcher;

  /// Called for every payload value that was unknown and fell back to its
  /// default (also printed in debug builds). Wire it to crash reporting when
  /// a bad tour means a bad release of your tour content.
  final void Function(String warning)? onWarning;

  @override
  Future<HintTour> fetch(String id) async {
    final uri = Uri.parse('$baseUrl/$id.json');
    final body = await fetcher(uri);
    final json = jsonDecode(body) as Map<String, dynamic>;
    return HintTour.fromJson(json, onWarning: onWarning);
  }
}
