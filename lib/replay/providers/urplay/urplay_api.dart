import 'dart:async';
import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// UR asked us to slow down; no request is sent until [retryAfter] has passed.
class UrPlayRateLimitedException implements Exception {
  final Duration retryAfter;

  const UrPlayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// What the stream endpoint answered. A refusal is data here, not an error: it says why a title cannot be watched.
class UrSourcesReply {
  final int statusCode;
  final Map<String, dynamic> body;

  const UrSourcesReply(this.statusCode, this.body);

  String? get message => body['message'] as String?;
}

/// Thin JSON access to the UR Play catalogue and its stream endpoint.
///
/// Catalogue answers are cached for a few minutes and at most [_maxInFlight] requests run at once, so opening a
/// page of shows does not fire dozens of calls together.
class UrPlayApi {
  static const _site = 'https://urplay.se/api/v1';
  static const _sources = 'https://media-api.urplay.se/config-streaming/v1/urplay/sources';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _ttl = Duration(minutes: 5);
  static const _maxCached = 200;
  static const _maxInFlight = 6;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, Map<String, dynamic>? body})> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _inFlight = 0;
  DateTime? _pausedUntil;

  UrPlayApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// One page of 24 results. UR ignores any page size, so [query] only carries filters and `start`.
  Future<Map<String, dynamic>> search(Map<String, String> query) async {
    final uri = Uri.parse('$_site/search').replace(queryParameters: query);
    return (await _cached(uri, missingIsNull: false))!;
  }

  /// The episodes of one series (one season), or null when the id is unknown.
  Future<Map<String, dynamic>?> seasonEpisodes(String seriesId) => _cached(
    Uri.parse('$_site/season_episodes').replace(queryParameters: {'seriesId': seriesId}),
    missingIsNull: true,
  );

  /// The page data of one programme, or null when the id is unknown.
  Future<Map<String, dynamic>?> episodeInfo(String programId) =>
      _cached(Uri.parse('$_site/episode_info').replace(queryParameters: {'programId': programId}), missingIsNull: true);

  /// Stream URLs for a programme. Never cached: the token in them is short lived and the answer depends on the viewer.
  Future<UrSourcesReply> sources(String programId) async {
    final response = await _send(Uri.parse('$_sources/$programId'));
    final data = response.data;
    final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    if (response.statusCode >= 500) throwIfHttpError(response);
    return UrSourcesReply(response.statusCode, body);
  }

  /// A playlist as text, or null when the server no longer serves it.
  Future<String?> playlist(Uri url) async {
    final response = await _send(url);
    if (response.statusCode == 404 || response.statusCode == 403) return null;
    throwIfHttpError(response);
    final data = response.data;
    return data is String ? data : null;
  }

  Future<Map<String, dynamic>?> _cached(Uri uri, {required bool missingIsNull}) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < _ttl) return hit.body;
    final body = await _json(uri, missingIsNull: missingIsNull);
    _cache.remove(key);
    _cache[key] = (at: _now(), body: body);
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    return body;
  }

  /// The site answers 404 or a bare 500 for an id it does not have, so both mean "missing" where [missingIsNull].
  Future<Map<String, dynamic>?> _json(Uri uri, {required bool missingIsNull}) async {
    final response = await _send(uri);
    if (missingIsNull && (response.statusCode == 404 || response.statusCode == 500)) return null;
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

  Future<MediaServerResponse> _send(Uri uri) async {
    final paused = _pausedUntil;
    if (paused != null && _now().isBefore(paused)) throw UrPlayRateLimitedException(paused.difference(_now()));
    await _enter();
    try {
      final response = await _http.get(uri.toString(), headers: _headers);
      if (response.statusCode == 429) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        _pausedUntil = _now().add(Duration(seconds: seconds));
        throw UrPlayRateLimitedException(Duration(seconds: seconds));
      }
      return response;
    } finally {
      _leave();
    }
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
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _inFlight--;
    }
  }
}
