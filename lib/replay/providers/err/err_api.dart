import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// ERR answered 429; [retryAfter] is how long it asked callers to wait.
class ErrRateLimitedException implements Exception {
  final Duration retryAfter;

  const ErrRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// What the CDN said about a stream manifest: a status and, for a 200, the playlist text.
typedef ErrManifestProbe = ({int status, String body});

/// Thin JSON access to ERR Jupiter's open catalogue, content and search endpoints.
class ErrApi {
  static const _services = 'https://services.err.ee';
  static const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _headers = {'Accept': 'application/json', 'User-Agent': _userAgent};

  /// The Estonian site; its metadata is Estonian. The Russian site is the same API with another domain.
  static const domain = 'jupiter.err.ee';
  static const rootId = 3905;

  static const _pageTtl = Duration(minutes: 5);
  static const _maxCached = 40;
  static const _bulkTimeout = Duration(seconds: 90);

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic>? body})> _cache = {};

  ErrApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A content page (the item, plus the season list when it belongs to a show), cached for a few minutes.
  /// Null when ERR has no such id.
  Future<Map<String, dynamic>?> contentPage(int id) => _cached(_contentUri(id));

  /// A content page that is never served from the cache: rights and stream addresses are read at the moment of use.
  Future<Map<String, dynamic>?> freshContentPage(int id, {Duration? timeout}) =>
      _data(_contentUri(id), timeout: timeout);

  /// A category page: `frontPage` rows for the big sections, `items` for the genre pages. Null for an unknown slug.
  Future<Map<String, dynamic>?> categoryPage(String url) async {
    final uri = Uri.parse(
      '$_services/api/v2/category/getByUrl',
    ).replace(queryParameters: {'url': url, 'domain': domain, 'page': 'web'});
    final data = await _cached(uri);
    return data?['category'] as Map<String, dynamic>?;
  }

  /// Every root item of the video catalogue (about 20 MB of JSON, 2 MB on the wire). Never cached here: the
  /// caller keeps what it needs, not the raw tree.
  Future<List<Map<String, dynamic>>> catalogueItems() async {
    final uri = Uri.parse('$_services/api/v2/series/getSeriesData').replace(queryParameters: {'type': 'video'});
    final data = await _data(uri, timeout: _bulkTimeout);
    final items = data?['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().toList() : const [];
  }

  /// Search cards for [phrase]: series, films, episodes and clips.
  Future<List<Map<String, dynamic>>> search(String phrase, {int limit = 40}) async {
    final options = jsonEncode({
      'phrase': phrase,
      'page': 1,
      'limit': limit,
      'searchTypes': ['video'],
      'viewTypes': ['series', 'movie', 'episode', 'clip'],
      'domain': domain,
      'rootId': rootId,
    });
    final uri = Uri.parse(
      '$_services/api/search/getVodContents2/',
    ).replace(queryParameters: {'type': 'video', 'options': options});
    final body = await _body(uri);
    final contents = (body?['video'] as Map?)?['contents'];
    return contents is List ? contents.whereType<Map<String, dynamic>>().toList() : const [];
  }

  /// Fetches an HLS master playlist. 403 and 404 are answers, not failures: the CDN refuses viewers outside Estonia
  /// for Estonia-only titles with an HTML page.
  Future<ErrManifestProbe> probeManifest(Uri manifest) async {
    final response = await _http.get(manifest.toString(), headers: {'User-Agent': _userAgent});
    final status = response.statusCode;
    if (status == 403 || status == 404) return (status: status, body: '');
    _checkStatus(response);
    final body = response.data;
    return (status: status, body: body is String ? body : '');
  }

  Uri _contentUri(int id) =>
      Uri.parse('$_services/api/v2/vodContent/getContentPageData').replace(queryParameters: {'contentId': '$id'});

  Future<Map<String, dynamic>?> _cached(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < _pageTtl) return hit.body;
    final body = await _data(uri);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), body: body);
    return body;
  }

  /// The `data` object of a `{apiVersion, data}` answer, or null for the 404 envelope.
  Future<Map<String, dynamic>?> _data(Uri uri, {Duration? timeout}) async {
    final body = await _body(uri, timeout: timeout);
    final data = body?['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  Future<Map<String, dynamic>?> _body(Uri uri, {Duration? timeout}) async {
    final response = await _http.get(uri.toString(), headers: _headers, timeout: timeout);
    if (response.statusCode == 404) return null;
    _checkStatus(response);
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Unexpected response shape',
      );
    }
    return body;
  }

  void _checkStatus(MediaServerResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw ErrRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
  }
}
