import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class StvrRateLimitedException implements Exception {
  final Duration retryAfter;

  const StvrRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A fetched playlist and the address it was finally served from, which differs when the CDN redirected.
class StvrPlaylist {
  final String body;
  final Uri finalUri;

  const StvrPlaylist(this.body, this.finalUri);
}

/// Thin access to the open archive endpoints of stvr.sk and to the CDN playlists they lead to.
class StvrApi {
  static const _site = 'https://www.stvr.sk';
  static const _agent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _jsonHeaders = {'Accept': 'application/json', 'User-Agent': _agent};
  static const _htmlHeaders = {'Accept': 'text/html', 'User-Agent': _agent};
  static const _jsonTtl = Duration(minutes: 5);
  static const _htmlTtl = Duration(minutes: 10);
  static const _cacheLimit = 80;

  final MediaServerHttpClient _http;
  final Map<String, ({DateTime at, Object body})> _cache = {};

  StvrApi(this._http);

  /// A page of the recordings listing. [series] accepts a series id or the show id of a page address, [date] is a
  /// `yyyy-mm-dd` air day, [query] matches recording names. Newest first unless [newestFirst] is false.
  Future<Map<String, dynamic>> archive({
    int page = 1,
    int size = 20,
    String? series,
    String? query,
    String? date,
    bool newestFirst = true,
  }) => _cachedJson(
    Uri.parse('$_site/json/tv/archiv').replace(
      queryParameters: {
        'archive': '1',
        'e': '1',
        'p': '$page',
        'l': '$size',
        'o': newestFirst ? 'desc' : 'asc',
        's': ?series,
        'q': ?query,
        'd': ?date,
      },
    ),
  );

  /// The site's own search, which lists shows. It needs at least three characters.
  Future<Map<String, dynamic>> siteSearch(String query) =>
      _cachedJson(Uri.parse('$_site/json/search/lite').replace(queryParameters: {'q': query}));

  /// The HTML of one page of a section such as `serialy`; its cards are the only list of shows by genre.
  Future<String> sectionPage(String section, int page) async {
    final uri = Uri.parse('$_site/televizia/archiv/$section').replace(queryParameters: {'page': '$page'});
    final hit = _fresh(uri.toString(), _htmlTtl);
    if (hit is String) return hit;
    final response = await _get(uri, _htmlHeaders);
    final body = response.data;
    if (body is! String) throw _badShape(uri, response.statusCode);
    _remember(uri.toString(), body);
    return body;
  }

  /// The stream description of a recording. Never cached: the signed address inside it expires. The answer also
  /// carries the caller's IP address, which is dropped here so nothing downstream can log it.
  Future<Map<String, dynamic>> stream(String programId) async {
    final uri = Uri.parse(
      '$_site/json/archive5f.json',
    ).replace(queryParameters: {'id': programId, 'b': 'mozilla', 'p': 'win', 'v': '97', 'f': '0', 'd': '1'});
    return _asJson(await _get(uri, _jsonHeaders), uri)..remove('IP');
  }

  /// A master or media playlist from the CDN.
  Future<StvrPlaylist> playlist(Uri url) async {
    final response = await _get(url, const {'User-Agent': _agent});
    final body = response.data;
    if (body is! String) throw _badShape(url, response.statusCode);
    return StvrPlaylist(body, response.effectiveUri ?? url);
  }

  Future<Map<String, dynamic>> _cachedJson(Uri uri) async {
    final key = uri.toString();
    final hit = _fresh(key, _jsonTtl);
    if (hit is Map<String, dynamic>) return hit;
    final body = _asJson(await _get(uri, _jsonHeaders), uri);
    _remember(key, body);
    return body;
  }

  Object? _fresh(String key, Duration ttl) {
    final hit = _cache[key];
    return hit != null && DateTime.now().difference(hit.at) < ttl ? hit.body : null;
  }

  void _remember(String key, Object body) {
    _cache.remove(key);
    _cache[key] = (at: DateTime.now(), body: body);
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
  }

  Future<MediaServerResponse> _get(Uri uri, Map<String, String> headers) async {
    final response = await _http.get(uri.toString(), headers: headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw StvrRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
    return response;
  }

  Map<String, dynamic> _asJson(MediaServerResponse response, Uri uri) {
    final data = response.data;
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Falls through to the shape error below.
    }
    throw _badShape(uri, response.statusCode);
  }

  MediaServerHttpException _badShape(Uri uri, int status) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: status,
    requestUri: uri,
    message: 'Unexpected response shape',
  );
}
