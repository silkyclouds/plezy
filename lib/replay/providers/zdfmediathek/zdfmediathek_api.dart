import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// ZDF refused a request because too many were made in a short time.
class ZdfRateLimitedException implements Exception {
  final Duration retryAfter;

  const ZdfRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// JSON access to the ZDFmediathek app API, which needs no key.
///
/// Requests are spaced out and catalogue pages are cached, because the site's own pages repeat the same documents.
class ZdfApi {
  static const _host = 'zdf-prod-futura.zdf.de';
  static const _base = 'https://$_host/mediathekV2';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _pageTtl = Duration(minutes: 5);
  static const _directoryTtl = Duration(days: 1);
  static const _maxCached = 60;

  final MediaServerHttpClient _http;
  final Duration _spacing;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  ZdfApi(this._http, {Duration gap = const Duration(milliseconds: 250), DateTime Function()? clock})
    : _spacing = gap,
      _now = clock ?? DateTime.now;

  Future<Map<String, dynamic>> startPage() => _cached('start-page', _pageTtl);

  Future<Map<String, dynamic>> categoriesOverview() => _cached('categories-overview', _pageTtl);

  /// Every show of the A to Z page, which is large and changes slowly.
  Future<Map<String, dynamic>> brandsAlphabetical() => _cached('document/sendungen-100', _directoryTtl);

  /// A show, season row, category or video document. Cached for a few minutes.
  Future<Map<String, dynamic>> document(String id) => _cached(_documentPath(id), _pageTtl);

  /// A document read now: the stream list of a video depends on the time of day and the viewer's country.
  Future<Map<String, dynamic>> freshDocument(String id) => _fetch(_uri(_documentPath(id)));

  /// One page of search results, 20 at a time. Follow [nextSearchPage] for more.
  Future<Map<String, dynamic>> search(String query) => _cached('search', _pageTtl, query: {'q': query});

  /// The next search page, from the `nextPageUrl` of the previous one. Links to other hosts are refused.
  Future<Map<String, dynamic>> nextSearchPage(String url) {
    final uri = Uri.parse(url);
    if (uri.host != _host) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        requestUri: uri,
        message: 'Search page link points to another host',
      );
    }
    return _cachedUri(uri, _pageTtl);
  }

  /// HTTP status of the first bytes of a stream. ZDF's CDN answers 403 where the viewer's country has no rights.
  Future<int> streamStatus(Uri url) async {
    final response = await _http.get(url.toString(), headers: {..._headers, 'Range': 'bytes=0-1023'});
    return response.statusCode;
  }

  String _documentPath(String id) => 'document/${Uri.encodeComponent(id)}';

  Uri _uri(String path, {Map<String, String>? query}) => Uri.parse('$_base/$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _cached(String path, Duration ttl, {Map<String, String>? query}) =>
      _cachedUri(_uri(path, query: query), ttl);

  Future<Map<String, dynamic>> _cachedUri(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.body;
    final body = await _fetch(uri);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), body: body);
    return body;
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) async {
    await _pace();
    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw ZdfRateLimitedException(Duration(seconds: seconds));
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

  /// Reserves the next request slot so concurrent callers queue up instead of bursting.
  Future<void> _pace() async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(_spacing);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
}
