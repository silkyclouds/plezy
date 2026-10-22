import 'dart:async';
import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import 'orftvthek_credentials.dart';

/// ORF asked for fewer requests; try again after [retryAfter].
class OrfRateLimitedException implements Exception {
  final Duration retryAfter;

  const OrfRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A JSON answer that is not the object or list the endpoint is documented to return.
class OrfUnexpectedResponseException implements Exception {
  final String path;

  const OrfUnexpectedResponseException(this.path);

  @override
  String toString() => 'Unexpected response from $path';
}

/// Thin JSON access to the ORF ON catalogue.
///
/// At most [maxConcurrent] requests run at once and nothing is sent while a Retry-After is running. Only small
/// answers are cached: an episode object embeds its chapters and a show's episode list can weigh megabytes.
class OrfApi {
  static const userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _headers = {'Accept': 'application/json', 'User-Agent': userAgent};
  static const _maxCached = 40;

  static const shortTtl = Duration(minutes: 5);
  static const longTtl = Duration(hours: 6);

  final MediaServerHttpClient _http;
  final OrfCredentials _credentials;
  final DateTime Function() _now;
  final int maxConcurrent;
  final LinkedHashMap<String, ({DateTime at, Object body})> _cache = LinkedHashMap();
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  DateTime? _pausedUntil;

  OrfApi(MediaServerHttpClient http, {DateTime Function()? now, int maxConcurrent = 3})
    : this._(http, OrfCredentials(http, _headers), now ?? DateTime.now, maxConcurrent);

  OrfApi._(this._http, this._credentials, this._now, this.maxConcurrent);

  /// Rows of the landing page.
  Future<List<dynamic>> pageStart() => _list('page/start', null, shortTtl);

  /// The editorial hero row of the landing page.
  Future<List<dynamic>> highlights() => _list('page/startpage/highlights', null, shortTtl);

  /// One editorial row, or `mostviewed`.
  Future<Map<String, dynamic>> lane(String id, {int page = 1, int limit = 20}) =>
      _object('lane/$id', _paging(page, limit), shortTtl);

  Future<Map<String, dynamic>> genres() => _object('genres', {'limit': '50'}, longTtl);

  Future<Map<String, dynamic>> genreEpisodes(String id, {int page = 1, int limit = 20}) =>
      _object('genre/$id/episodes', _paging(page, limit), shortTtl);

  Future<Map<String, dynamic>> genreProfiles(String id, {int page = 1, int limit = 20}) =>
      _object('genre/$id/profiles', _paging(page, limit), shortTtl);

  /// Every episode, newest first.
  Future<Map<String, dynamic>> episodes({int page = 1, int limit = 20}) =>
      _object('episodes', _paging(page, limit), shortTtl);

  /// A page of the alphabetical list of shows. Heavy at the largest page size, so the caller keeps what it needs.
  Future<Map<String, dynamic>> profiles({int page = 1, int limit = 500}) =>
      _object('profiles', _paging(page, limit), Duration.zero);

  Future<Map<String, dynamic>> profile(int id) => _object('profile/$id', null, longTtl);

  /// A page of a show's episodes. Heavy (each episode embeds its chapters), so never cached here.
  Future<Map<String, dynamic>> profileEpisodes(int id, {int page = 1, int limit = 50}) =>
      _object('profile/$id/episodes', _paging(page, limit), Duration.zero);

  /// A programme with its stream list. Never cached: rights and stream addresses change with the moment.
  Future<Map<String, dynamic>> episode(int id) => _object('episode/$id', null, Duration.zero);

  Future<Map<String, dynamic>> segment(int id) => _object('segment/$id', null, Duration.zero);

  Future<Map<String, dynamic>> subtitle(int id) => _object('subtitle/$id', null, longTtl);

  Future<Map<String, dynamic>> search(String query) => _object('search/${Uri.encodeComponent(query)}', null, shortTtl);

  /// Where a stream address ends up after its redirects. Sent without credentials: it is not an API host.
  Future<Uri> resolveStream(Uri address) async {
    final response = await _http.get(address.toString(), headers: const {'User-Agent': userAgent});
    throwIfHttpError(response);
    return response.effectiveUri ?? address;
  }

  Map<String, String> _paging(int page, int limit) => {'page': '$page', 'limit': '$limit'};

  Future<Map<String, dynamic>> _object(String path, Map<String, String>? query, Duration ttl) async {
    final body = await _cached(path, query, ttl);
    if (body is Map<String, dynamic>) return body;
    throw OrfUnexpectedResponseException(path);
  }

  Future<List<dynamic>> _list(String path, Map<String, String>? query, Duration ttl) async {
    final body = await _cached(path, query, ttl);
    if (body is List) return body;
    throw OrfUnexpectedResponseException(path);
  }

  Future<Object> _cached(String path, Map<String, String>? query, Duration ttl) async {
    final key = '$path?${query ?? ''}';
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.body;
    final body = await _fetch(path, query);
    if (ttl > Duration.zero) {
      _cache.remove(key);
      _cache[key] = (at: _now(), body: body);
      if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
    }
    return body;
  }

  Future<Object> _fetch(String path, Map<String, String>? query) async {
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && _now().isBefore(pausedUntil)) {
      throw OrfRateLimitedException(pausedUntil.difference(_now()));
    }
    await _acquire();
    try {
      return await _request(path, query);
    } finally {
      _release();
    }
  }

  /// One authenticated GET. A 401 means the pair in use is stale, so the page is read again and the call retried once.
  Future<Object> _request(String path, Map<String, String>? query) async {
    var settings = await _credentials.current();
    for (var attempt = 0; ; attempt++) {
      final uri = settings.baseUri.resolve(path).replace(queryParameters: query);
      final response = await _http.get(uri.toString(), headers: {..._headers, 'Authorization': settings.authorization});
      if (response.statusCode == 401 && attempt == 0) {
        settings = await _credentials.refresh();
        continue;
      }
      if (response.statusCode == 429) {
        final retry = Duration(seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 60);
        _pausedUntil = _now().add(retry);
        throw OrfRateLimitedException(retry);
      }
      throwIfHttpError(response);
      final data = response.data;
      if (data is Map<String, dynamic> || data is List) return data as Object;
      throw OrfUnexpectedResponseException(path);
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

/// True for a 404 from the API: the programme or show is gone.
bool orfIsNotFound(MediaServerHttpException error) => error.statusCode == 404;
