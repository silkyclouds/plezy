import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../utils/media_server_http_client.dart';

/// PBS asked us to slow down; no request is sent until [retryAfter] has passed.
class PbsRateLimitedException implements Exception {
  final Duration retryAfter;

  const PbsRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// What the stream redirector answered for one encoding.
class PbsRedirect {
  /// The file to play, when the redirector handed one out.
  final Uri? url;

  /// The redirector refused the caller's region.
  final bool refusedRegion;

  const PbsRedirect({this.url, this.refusedRegion = false});
}

/// Access to the pbs.org routes the website itself calls, with one request per second as `robots.txt` asks.
///
/// Catalogue answers are cached for five minutes. The player page and stream redirects are never cached: stream
/// addresses carry a session segment that changes on every call.
class PbsApi {
  static const _site = 'https://www.pbs.org';
  static const _headers = {'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'};
  static const _ttl = Duration(minutes: 5);
  static const _maxCached = 40;

  final MediaServerHttpClient _http;

  /// Minimum time between the starts of two requests.
  final Duration interval;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, Object? body})> _cache = LinkedHashMap();
  Future<void> _tail = Future.value();
  DateTime? _lastRequest;
  DateTime? _pausedUntil;

  PbsApi(this._http, {this.interval = const Duration(seconds: 1), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// One page of the search index. Passport-only videos are left out: they cannot be played without an account.
  Future<Map<String, dynamic>> search(String query, {int limit = 20, int start = 0}) async {
    final uri = Uri.parse('$_site/api/v1/search/').replace(
      queryParameters: {
        'q': query,
        'rank': 'relevance',
        'filter_video_availability': 'public',
        'page': '1',
        'start': '$start',
        'limit': '$limit',
      },
    );
    final body = await _cachedJson(uri);
    return body is Map<String, dynamic> ? body : const {};
  }

  /// Full episodes of a season that the caller may play. Empty when the season has none.
  Future<List<Map<String, dynamic>>> seasonEpisodes(String showSlug, String seasonCid) =>
      _list('$_site/api/show/$showSlug/season/$seasonCid/episodes/');

  /// Clips and previews of a season.
  Future<List<Map<String, dynamic>>> seasonExtras(String showSlug, String seasonCid) =>
      _list('$_site/api/show/$showSlug/season/$seasonCid/extras/');

  /// The HTML of a website page, or null when it does not exist. Pages run to half a megabyte, so callers keep what
  /// they read from them rather than the page.
  Future<String?> page(String path) async {
    final response = await _fetch(Uri.parse('$_site$path'));
    return response.statusCode == 404 || response.data is! String ? null : response.data as String;
  }

  /// The player page of a video. Null when PBS has no such video.
  Future<String?> playerPage(String mediaId) async {
    final response = await _fetch(Uri.parse('https://player.pbs.org/portalplayer/$mediaId/'));
    return response.statusCode == 404 || response.data is! String ? null : response.data as String;
  }

  /// Asks the redirector for the file behind one encoding address, without downloading the file.
  Future<PbsRedirect> redirect(Uri encoding) async {
    final response = await _fetch(encoding.replace(queryParameters: {'format': 'json'}), passRefusal: true);
    final body = _decode(response.data);
    final code = body is Map && body['http_code'] is num ? (body['http_code'] as num).toInt() : response.statusCode;
    if (code == 403 || response.statusCode == 403) return const PbsRedirect(refusedRegion: true);
    final url = body is Map ? body['url'] : null;
    return PbsRedirect(url: url is String ? Uri.tryParse(url) : null);
  }

  Future<List<Map<String, dynamic>>> _list(String url) async {
    final body = await _cachedJson(Uri.parse(url));
    return body is List
        ? [
            for (final item in body)
              if (item is Map<String, dynamic>) item,
          ]
        : const [];
  }

  Future<Object?> _cachedJson(Uri uri) => _cached(uri, (response) => _decode(response.data));

  Future<Object?> _cached(Uri uri, Object? Function(MediaServerResponse) read) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < _ttl) return hit.body;
    final response = await _fetch(uri);
    final body = response.statusCode == 404 ? null : read(response);
    _cache.remove(key);
    _cache[key] = (at: _now(), body: body);
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    return body;
  }

  /// The API labels its JSON as plain text, so the body is decoded here whatever the content type says.
  Object? _decode(Object? data) {
    if (data is! String) return data;
    try {
      return jsonDecode(data);
    } on FormatException {
      return null;
    }
  }

  Future<MediaServerResponse> _fetch(Uri uri, {bool passRefusal = false}) {
    final paused = _pausedUntil;
    if (paused != null && _now().isBefore(paused)) {
      return Future.error(PbsRateLimitedException(paused.difference(_now())));
    }
    return _paced(() async {
      final response = await _http.get(uri.toString(), headers: _headers);
      if (response.statusCode == 429) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        _pausedUntil = _now().add(Duration(seconds: seconds));
        throw PbsRateLimitedException(Duration(seconds: seconds));
      }
      final expected = response.statusCode == 404 || (passRefusal && response.statusCode == 403);
      if (!expected) throwIfHttpError(response);
      return response;
    });
  }

  /// Runs [send] after the previous request has had [interval] to itself.
  Future<T> _paced<T>(Future<T> Function() send) {
    final turn = _tail.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final wait = interval - _now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastRequest = _now();
      return send();
    });
    _tail = turn.then<void>((_) {}, onError: (Object _) {});
    return turn;
  }
}
