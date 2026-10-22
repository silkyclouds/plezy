import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class BbcIplayerRateLimitedException implements Exception {
  final Duration retryAfter;

  const BbcIplayerRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Thin JSON access to the iPlayer Business Layer, the catalogue API behind bbc.co.uk/iplayer.
class BbcIplayerApi {
  static const _iblBase = 'https://ibl.api.bbci.co.uk/ibl/v1/';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _ttl = Duration(minutes: 5);
  static const _maxCached = 200;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};

  BbcIplayerApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A catalogue answer, cached for a few minutes unless [fresh] asks for the live state.
  Future<Map<String, dynamic>> ibl(String path, {Map<String, String>? query, bool fresh = false}) async {
    final url = Uri.parse('$_iblBase$path').replace(queryParameters: query).toString();
    final hit = _cache[url];
    if (!fresh && hit != null && _now().difference(hit.at) < _ttl) return hit.body;

    final response = await get(url);
    throwIfHttpError(response);
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: response.requestUri,
        message: 'Unexpected response shape',
      );
    }
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[url] = (at: _now(), body: body);
    return body;
  }

  /// Any URL with the identifying headers. Status codes are the caller's to read, except rate limiting.
  Future<MediaServerResponse> get(String url) async {
    final response = await _http.get(url, headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw BbcIplayerRateLimitedException(Duration(seconds: seconds));
    }
    return response;
  }
}
