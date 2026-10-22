import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// RTVE refused a request because too many were made in a short time.
class RtvePlayRateLimitedException implements Exception {
  final Duration retryAfter;

  const RtvePlayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// What a manifest request answered; the body is only kept for a successful answer.
class RtveProbe {
  final int status;
  final Map<String, String> headers;
  final String body;

  const RtveProbe({required this.status, required this.headers, this.body = ''});
}

/// Thin access to RTVE's open catalogue, its search and the stream-resolution endpoint.
class RtvePlayApi {
  static const _catalogue = 'https://www.rtve.es/api/';
  static const _search = 'https://api.rtve.es/api/search/';
  static const _streamImage = 'https://www.rtve.es/ztnr/movil/thumbnail/rtveplayw/videos/';
  static const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _jsonHeaders = {'Accept': 'application/json', 'User-Agent': _userAgent};
  static const _anyHeaders = {'Accept': '*/*', 'User-Agent': _userAgent};
  static const _ttl = Duration(minutes: 5);
  static const _maxCached = 200;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};

  RtvePlayApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A catalogue document such as `programas/123.json` or `programas/123/temporadas`. Cached for a few minutes.
  Future<Map<String, dynamic>> catalogue(String path, {Map<String, String>? query}) =>
      _cached(Uri.parse('$_catalogue$path').replace(queryParameters: _nonEmpty(query)));

  /// Programmes matching [text].
  Future<Map<String, dynamic>> searchPrograms(String text, {int size = 20}) => _cached(
    Uri.parse('${_search}programs').replace(
      queryParameters: {
        'search': text,
        'page': '1',
        'context': 'tve',
        'size': '$size',
        'isExpanded': 'true',
        'isChild': 'true',
        'useOntology': 'false',
      },
    ),
  );

  /// Full-length videos matching [text].
  Future<Map<String, dynamic>> searchContents(String text, {int size = 20}) => _cached(
    Uri.parse('${_search}contents').replace(
      queryParameters: {
        'search': text,
        'page': '1',
        'size': '$size',
        'context': 'tve',
        'type': 'completo',
        'tipology': 'video',
        'isExpanded': 'true',
        'isChild': 'true',
        'useOntology': 'false',
      },
    ),
  );

  /// The obfuscated stream list of a video, as the text RTVE serves for it. Never cached: it answers for blocked
  /// videos too, and the verdict only shows on the manifest.
  Future<String> streamImage(String videoId) async {
    final uri = Uri.parse('$_streamImage$videoId.png').replace(queryParameters: {'q': 'v2'});
    final response = await _http.get(uri.toString(), headers: _anyHeaders);
    _throwIfRateLimited(response);
    throwIfHttpError(response);
    final data = response.data;
    if (data is! String) throw _unexpectedShape(uri, response.statusCode);
    return data;
  }

  /// Requests a manifest. A refusal comes back as a [RtveProbe], not as an exception, because the status is the
  /// answer to "may this viewer play it".
  Future<RtveProbe> probe(Uri manifest) async {
    final response = await _http.get(manifest.toString(), headers: _anyHeaders);
    _throwIfRateLimited(response);
    final data = response.data;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    return RtveProbe(status: response.statusCode, headers: response.headers, body: ok && data is String ? data : '');
  }

  Future<Map<String, dynamic>> _cached(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    final now = _now();
    if (hit != null && now.difference(hit.at) < _ttl) return hit.body;
    final response = await _http.get(key, headers: _jsonHeaders);
    _throwIfRateLimited(response);
    throwIfHttpError(response);
    final data = response.data;
    if (data is! Map<String, dynamic>) throw _unexpectedShape(uri, response.statusCode);
    _remember(key, data, now);
    return data;
  }

  void _remember(String key, Map<String, dynamic> body, DateTime now) {
    if (_cache.length >= _maxCached) _cache.removeWhere((_, v) => now.difference(v.at) >= _ttl);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: now, body: body);
  }

  void _throwIfRateLimited(MediaServerResponse response) {
    if (response.statusCode != 429) return;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
    throw RtvePlayRateLimitedException(Duration(seconds: seconds));
  }

  MediaServerHttpException _unexpectedShape(Uri uri, int status) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: status,
    requestUri: uri,
    message: 'Unexpected response shape',
  );

  Map<String, String>? _nonEmpty(Map<String, String>? query) => query == null || query.isEmpty ? null : query;
}
