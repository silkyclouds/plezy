import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class ThreeCatRateLimitedException implements Exception {
  final Duration retryAfter;

  const ThreeCatRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// An answer that is not the JSON object the endpoint is documented to return.
class ThreeCatUnexpectedResponseException implements Exception {
  final Uri uri;

  const ThreeCatUnexpectedResponseException(this.uri);

  @override
  String toString() => 'Unexpected response from $uri';
}

/// Thin access to the open 3Cat catalogue, its media resolver and its A-Z page.
///
/// At most [maxConcurrent] requests run at once. After a 429 nothing is sent until its Retry-After has passed.
class ThreeCatApi {
  static const catalogueHost = 'api.3cat.cat';
  static const _mediaHost = 'api-media.3cat.cat';
  static const _siteHost = 'www.3cat.cat';
  static const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';

  /// Arguments the catalogue refuses to answer without.
  static const _fixedQuery = {
    '_format': 'json',
    'sdom': 'img',
    'version': '2.0',
    'cache': '180',
    'https': 'true',
    'master': 'yes',
  };
  static const _maxCached = 30;
  static const shortTtl = Duration(minutes: 5);
  static const dayTtl = Duration(hours: 24);

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final int maxConcurrent;
  final LinkedHashMap<String, ({DateTime at, Object body})> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  DateTime? _pausedUntil;

  ThreeCatApi(this._http, {DateTime Function()? now, this.maxConcurrent = 4}) : _now = now ?? DateTime.now;

  /// A catalogue endpoint such as `tot`, `videos` or `programestv/54076/`, with the fixed arguments added.
  Future<Map<String, dynamic>> catalogue(String endpoint, [Map<String, String> query = const {}]) =>
      catalogueUri(Uri.https(catalogueHost, '/$endpoint', {..._fixedQuery, ...query}));

  /// A catalogue address taken from the broadcaster's own data. Other hosts are refused.
  Future<Map<String, dynamic>> catalogueUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host != catalogueHost) throw ThreeCatUnexpectedResponseException(uri);
    return _object(uri, shortTtl);
  }

  /// How to play a video. Never cached: the stream address and the rights change with the moment.
  Future<Map<String, dynamic>> media(String videoId) => _object(
    Uri.https(_mediaHost, '/pvideo/media.jsp', {'media': 'video', 'idint': videoId, 'format': 'dm'}),
    Duration.zero,
  );

  /// The A-Z page of the website, which is the only place that lists every programme.
  Future<String> indexPage() async {
    final uri = Uri.https(_siteHost, '/3cat/tot-cataleg/tot/');
    final hit = _cache[uri.toString()];
    if (hit != null && _now().difference(hit.at) < dayTtl) return hit.body as String;
    final response = await _fetch(uri, accept: 'text/html');
    final body = response.data;
    if (body is! String) throw ThreeCatUnexpectedResponseException(uri);
    _remember(uri.toString(), body);
    return body;
  }

  /// The status of a one-byte range request, which tells whether the viewer's address may fetch the stream.
  Future<int> probe(Uri url) async {
    final response = await _fetch(url, accept: '*/*', headers: const {'Range': 'bytes=0-0'}, checkStatus: false);
    return response.statusCode;
  }

  Future<Map<String, dynamic>> _object(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (ttl > Duration.zero && hit != null && _now().difference(hit.at) < ttl) return hit.body as Map<String, dynamic>;
    final response = await _fetch(uri, accept: 'application/json');
    final body = _asObject(response.data);
    if (body == null) throw ThreeCatUnexpectedResponseException(uri);
    if (ttl > Duration.zero) _remember(key, body);
    return body;
  }

  Map<String, dynamic>? _asObject(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is! String) return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void _remember(String key, Object body) {
    _cache.remove(key);
    _cache[key] = (at: _now(), body: body);
    if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
  }

  Future<MediaServerResponse> _fetch(
    Uri uri, {
    required String accept,
    Map<String, String> headers = const {},
    bool checkStatus = true,
  }) async {
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && _now().isBefore(pausedUntil)) {
      throw ThreeCatRateLimitedException(pausedUntil.difference(_now()));
    }
    await _acquire();
    try {
      final response = await _http.get(
        uri.toString(),
        headers: {'Accept': accept, 'User-Agent': _userAgent, ...headers},
        timeout: const Duration(seconds: 20),
      );
      if (response.statusCode == 429) {
        final retry = Duration(seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 60);
        _pausedUntil = _now().add(retry);
        throw ThreeCatRateLimitedException(retry);
      }
      if (checkStatus) throwIfHttpError(response);
      return response;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _running--;
    } else {
      _waiting.removeFirst().complete();
    }
  }
}
