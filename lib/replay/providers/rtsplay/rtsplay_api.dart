import 'dart:async';
import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked us to slow down; no request is sent until [retryAfter] has passed.
class RtsPlayRateLimitedException implements Exception {
  final Duration retryAfter;

  const RtsPlayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Thin JSON access to the SRG Integration Layer, RTS business unit.
///
/// Lists are cached for as long as the server allows (20 minutes) and at most [_maxInFlight] requests
/// run at once, so opening a category page does not fire a dozen calls together.
class RtsPlayApi {
  static const _base = 'https://il.srgssr.ch/integrationlayer/2.0';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _ttl = Duration(minutes: 20);
  static const _maxCached = 150;
  static const _maxInFlight = 4;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, Map<String, dynamic>? body})> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _inFlight = 0;
  DateTime? _pausedUntil;

  RtsPlayApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A catalogue call under the RTS business unit, such as `topicList/tv`. Null when the server has no such resource.
  Future<Map<String, dynamic>?> unit(String path, [Map<String, String>? query]) =>
      _cached(Uri.parse('$_base/rts/$path').replace(queryParameters: query));

  /// A pagination link exactly as the server returned it.
  Future<Map<String, dynamic>?> link(String absoluteUrl) => _cached(Uri.parse(absoluteUrl));

  /// Playback resolution for a video id. Never cached: stream URLs and rights change with the moment.
  Future<Map<String, dynamic>?> mediaComposition(String videoId) =>
      _fetch(Uri.parse('$_base/mediaComposition/byUrn/urn:rts:video:$videoId'));

  Future<Map<String, dynamic>?> _cached(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < _ttl) return hit.body;
    final body = await _fetch(uri);
    _cache.remove(key);
    _cache[key] = (at: _now(), body: body);
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    return body;
  }

  Future<Map<String, dynamic>?> _fetch(Uri uri) async {
    final paused = _pausedUntil;
    if (paused != null && _now().isBefore(paused)) throw RtsPlayRateLimitedException(paused.difference(_now()));
    await _enter();
    try {
      return _body(await _http.get(uri.toString(), headers: _headers), uri);
    } finally {
      _leave();
    }
  }

  Map<String, dynamic>? _body(MediaServerResponse response, Uri uri) {
    if (response.statusCode == 404) return null;
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _pausedUntil = _now().add(Duration(seconds: seconds));
      throw RtsPlayRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Unexpected response shape',
      );
    }
    return data;
  }

  Future<void> _enter() async {
    if (_inFlight < _maxInFlight) {
      _inFlight++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _leave() {
    if (_waiting.isEmpty) {
      _inFlight--;
    } else {
      _waiting.removeFirst().complete();
    }
  }
}
