import '../../../utils/media_server_http_client.dart';
import '../../../exceptions/media_server_exceptions.dart';

/// The broadcaster refused a request because too many were made in a short time.
class ReplayRateLimitedException implements Exception {
  final Duration retryAfter;

  const ReplayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Thin JSON access to ARTE's open catalogue and player endpoints.
class ArteApi {
  static const _base = 'https://api.arte.tv/api';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  final MediaServerHttpClient _http;
  final String language;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};

  ArteApi(this._http, {this.language = 'fr'});

  static const _emacTtl = Duration(minutes: 5);

  /// A catalogue page, collection, program or search page. Responses are cached for a few minutes.
  Future<Map<String, dynamic>> emac(String path, {Map<String, String>? query}) =>
      _cached(Uri.parse('$_base/emac/v4/$language/web/$path').replace(queryParameters: query), _emacTtl);

  /// A pagination link exactly as the server returned it.
  Future<Map<String, dynamic>> link(String absoluteUrl) => _cached(Uri.parse(absoluteUrl), _emacTtl);

  /// Playback configuration for a video id. Never cached: the stream URL and rights change with the moment.
  Future<Map<String, dynamic>> playerConfig(String videoId) =>
      _fetch(Uri.parse('$_base/player/v2/config/$language/$videoId'));

  Future<Map<String, dynamic>> _cached(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.body;
    final body = await _fetch(uri);
    _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) async {
    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw ReplayRateLimitedException(Duration(seconds: seconds));
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
}
