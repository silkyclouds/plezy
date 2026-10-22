import 'dart:async';
import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class NrkRateLimitedException implements Exception {
  final Duration retryAfter;

  const NrkRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A JSON answer that is not the object or list the endpoint is documented to return.
class NrkUnexpectedResponseException implements Exception {
  final Uri uri;

  const NrkUnexpectedResponseException(this.uri);

  @override
  String toString() => 'Unexpected response from $uri';
}

/// Thin JSON access to the open NRK TV catalogue (PS API), its search and its playback manifests.
///
/// At most [maxConcurrent] requests run at once. After a 429 nothing is sent until its Retry-After has passed.
class NrkApi {
  static const _psApi = 'psapi.nrk.no';
  static const _searchHost = 'search.tv.api.nrk.no';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _maxCached = 40;

  static const shortTtl = Duration(minutes: 10);
  static const longTtl = Duration(hours: 6);

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final int maxConcurrent;
  final LinkedHashMap<String, ({DateTime at, Object body})> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  DateTime? _pausedUntil;

  NrkApi(this._http, {DateTime Function()? now, this.maxConcurrent = 4}) : _now = now ?? DateTime.now;

  /// The list of category pages.
  Future<Map<String, dynamic>> pageList() => _object(_psUri('/tv/pages'), longTtl);

  /// A page of rails: `frontpage` or a category id. Pages are large, so the caller keeps what it makes of them.
  Future<Map<String, dynamic>> page(String id) => _object(_psUri('/tv/pages/$id'), Duration.zero);

  /// The A-Z letters, in the order the index lists them.
  Future<List<dynamic>> letters() => _list(_psUri('/medium/tv/letters'), longTtl);

  /// Every title that starts with [letter].
  Future<List<dynamic>> indexLetter(String letter) =>
      _list(_psUri('/medium/tv/letters/${letter.toLowerCase()}/indexelements'), Duration.zero);

  Future<Map<String, dynamic>> series(String seriesId) => _object(_psUri('/tv/catalog/series/$seriesId'), shortTtl);

  Future<Map<String, dynamic>> season(String seriesId, String season) =>
      _object(_psUri('/tv/catalog/series/$seriesId/seasons/$season'), shortTtl);

  /// A programme's catalogue page: details and, in `moreInformation`, the geographic flag.
  Future<Map<String, dynamic>> program(String programId) => _object(_psUri('/tv/catalog/programs/$programId'), longTtl);

  /// What the player knows about a programme, among it the series and season it belongs to.
  Future<Map<String, dynamic>> metadata(String programId) =>
      _object(_psUri('/playback/metadata/program/$programId'), longTtl);

  Future<Map<String, dynamic>> search(String query) =>
      _object(Uri.https(_searchHost, '/search', {'q': query, 'maxResultsPerPage': '50'}), const Duration(minutes: 5));

  /// The stream description of a programme. Never cached: rights and the stream address change with the moment.
  Future<Map<String, dynamic>> manifest(String programId) =>
      _object(_psUri('/playback/manifest/program/$programId'), Duration.zero);

  Uri _psUri(String path) => Uri.https(_psApi, path);

  Future<Map<String, dynamic>> _object(Uri uri, Duration ttl) async {
    final body = await _cached(uri, ttl);
    if (body is Map<String, dynamic>) return body;
    throw NrkUnexpectedResponseException(uri);
  }

  Future<List<dynamic>> _list(Uri uri, Duration ttl) async {
    final body = await _cached(uri, ttl);
    if (body is List) return body;
    throw NrkUnexpectedResponseException(uri);
  }

  Future<Object> _cached(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.body;
    final body = await _fetch(uri);
    if (ttl > Duration.zero) {
      _cache.remove(key);
      _cache[key] = (at: _now(), body: body);
      if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
    }
    return body;
  }

  Future<Object> _fetch(Uri uri) async {
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && _now().isBefore(pausedUntil)) {
      throw NrkRateLimitedException(pausedUntil.difference(_now()));
    }
    await _acquire();
    try {
      final response = await _http.get(uri.toString(), headers: _headers);
      if (response.statusCode == 429) {
        final retry = Duration(seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 60);
        _pausedUntil = _now().add(retry);
        throw NrkRateLimitedException(retry);
      }
      throwIfHttpError(response);
      final data = response.data;
      if (data is Map<String, dynamic> || data is List) return data as Object;
      throw NrkUnexpectedResponseException(uri);
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

/// True for a 404 from the API: the series, programme or season is gone.
bool nrkIsNotFound(MediaServerHttpException error) => error.statusCode == 404;
