import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The NFB asked us to slow down; no request is sent until [retryAfter] has passed.
class NfbRateLimitedException implements Exception {
  final Duration retryAfter;

  const NfbRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Access to the nfb.ca routes the website itself calls: the paged catalogue the site's search page reads, the
/// series, film and player pages, and the "recently added" feed.
///
/// Requests are spaced so a browsing session stays far below any limit. Catalogue answers are cached for a few
/// minutes. Player pages are never cached: their stream address is signed and expires.
class NfbApi {
  static const site = 'https://www.nfb.ca';
  static const _catalogue = 'https://publicapi.nfb.ca/api/v5';
  static const _headers = {'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'};
  static const _ttl = Duration(minutes: 5);
  static const _maxCached = 40;

  final MediaServerHttpClient _http;
  final Duration _interval;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, Object body})> _cache = LinkedHashMap();
  Future<void> _tail = Future.value();
  DateTime? _lastRequest;
  DateTime? _pausedUntil;

  NfbApi(this._http, {this._interval = const Duration(milliseconds: 300), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// One page of English films. [sort] applies to browsing only: the catalogue refuses it together with [query].
  Future<Map<String, dynamic>> films({String? query, String? genre, String? sort, int page = 1, int size = 24}) {
    final params = {..._common, 'size': '$size', 'page': '$page'};
    if (query != null) {
      params['query'] = query;
    } else if (sort != null) {
      params['sort'] = sort;
    }
    if (genre != null) params['genre'] = genre;
    return _catalogueJson('films', params);
  }

  /// Every English series, which is a short list.
  Future<Map<String, dynamic>> series() =>
      _catalogueJson('series', {..._common, 'size': '100', 'page': '1', 'sort': 'title'});

  /// The HTML of a series page, or null when the NFB has no such series.
  Future<String?> seriesPage(String slug) => _page('$site/series/${Uri.encodeComponent(slug)}/');

  /// The HTML of a film or episode page, or null when the NFB has no such film. Episode addresses redirect to the
  /// page nested under their series.
  Future<String?> filmPage(String slug) => _page('$site/film/${Uri.encodeComponent(slug)}/');

  /// The player page of a film. It carries the signed stream address, so it is fetched at play time only.
  Future<String?> playerPage(String slug) => _page('$site/film/${Uri.encodeComponent(slug)}/embed/player/');

  /// The "recently added" RSS feed, or null when it is not served.
  Future<String?> recentFeed() => _cachedText('$site/feeds/new_additions/');

  static const _common = {'language': 'en', 'locale': 'en', 'subset': 'nfb/published'};

  Future<Map<String, dynamic>> _catalogueJson(String path, Map<String, String> params) async {
    final uri = Uri.parse('$_catalogue/$path').replace(queryParameters: params);
    final key = uri.toString();
    final hit = _fresh(key);
    if (hit is Map<String, dynamic>) return hit;
    final body = _asJson(await _fetch(uri), uri);
    _remember(key, body);
    return body;
  }

  Future<String?> _cachedText(String url) async {
    final hit = _fresh(url);
    if (hit is String) return hit;
    final text = await _page(url);
    if (text != null) _remember(url, text);
    return text;
  }

  Future<String?> _page(String url) async {
    final response = await _fetch(Uri.parse(url), allowMissing: true);
    final data = response.data;
    return response.statusCode == 404 || data is! String ? null : data;
  }

  Map<String, dynamic> _asJson(MediaServerResponse response, Uri uri) {
    var data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        data = null;
      }
    }
    if (data is Map<String, dynamic>) return data;
    throw MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      statusCode: response.statusCode,
      requestUri: uri,
      message: 'Unexpected response shape',
    );
  }

  Object? _fresh(String key) {
    final hit = _cache[key];
    return hit != null && _now().difference(hit.at) < _ttl ? hit.body : null;
  }

  void _remember(String key, Object body) {
    _cache.remove(key);
    _cache[key] = (at: _now(), body: body);
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<MediaServerResponse> _fetch(Uri uri, {bool allowMissing = false}) {
    final paused = _pausedUntil;
    if (paused != null && _now().isBefore(paused)) {
      return Future.error(NfbRateLimitedException(paused.difference(_now())));
    }
    return _paced(() async {
      final response = await _http.get(uri.toString(), headers: _headers);
      if (response.statusCode == 429) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        _pausedUntil = _now().add(Duration(seconds: seconds));
        throw NfbRateLimitedException(Duration(seconds: seconds));
      }
      if (!(allowMissing && response.statusCode == 404)) throwIfHttpError(response);
      return response;
    });
  }

  /// Runs [send] after the previous request has had [_interval] to itself.
  Future<T> _paced<T>(Future<T> Function() send) {
    final turn = _tail.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final wait = _interval - _now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastRequest = _now();
      return send();
    });
    _tail = turn.then<void>((_) {}, onError: (Object _) {});
    return turn;
  }
}
