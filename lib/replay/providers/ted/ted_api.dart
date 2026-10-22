import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// TED refused a request because too many were made in a short time.
class TedRateLimitedException implements Exception {
  final Duration retryAfter;

  const TedRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The GraphQL endpoint answered without data, for example because a query did not validate.
class TedApiException implements Exception {
  final String message;

  const TedApiException(this.message);

  @override
  String toString() => 'TED API error: $message';
}

/// Access to the open GraphQL endpoint the ted.com web app uses, and to the HLS masters it points at.
class TedApi {
  static const graphqlUrl = 'https://www.ted.com/graphql';
  static const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _headers = {'Accept': 'application/json', 'Content-Type': 'application/json', 'User-Agent': _userAgent};
  static const _ttl = Duration(minutes: 5);
  static const _cacheLimit = 100;
  static const _defaultRetryAfter = Duration(seconds: 60);

  final MediaServerHttpClient _http;
  final DateTime Function() _clock;
  final Map<String, ({DateTime at, Map<String, dynamic> data})> _cache = {};
  DateTime? _blockedUntil;

  TedApi(this._http, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The `data` object of one GraphQL query. Answers are cached for a few minutes, keyed by the query text.
  Future<Map<String, dynamic>> query(String graphql) async {
    final hit = _cache[graphql];
    if (hit != null && _clock().difference(hit.at) < _ttl) return hit.data;
    _throwIfCoolingDown();

    final response = await _http.post(graphqlUrl, headers: _headers, body: {'query': graphql});
    _throwIfRateLimited(response);
    throwIfHttpError(response);

    final body = response.data;
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) throw TedApiException(_firstError(body));
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[graphql] = (at: _clock(), data: data);
    return data;
  }

  /// The text of an HLS master playlist. Never cached: it is read once per playback.
  Future<String> master(Uri url) async {
    _throwIfCoolingDown();
    final response = await _http.get(url.toString(), headers: const {'User-Agent': _userAgent});
    _throwIfRateLimited(response);
    throwIfHttpError(response);
    final text = response.data;
    if (text is! String) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: url,
        message: 'Unexpected playlist shape',
      );
    }
    return text;
  }

  void clearCache() => _cache.clear();

  void _throwIfCoolingDown() {
    final until = _blockedUntil;
    if (until != null && until.isAfter(_clock())) throw TedRateLimitedException(until.difference(_clock()));
  }

  void _throwIfRateLimited(MediaServerResponse response) {
    if (response.statusCode != 429) return;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final wait = seconds == null ? _defaultRetryAfter : Duration(seconds: seconds);
    _blockedUntil = _clock().add(wait);
    throw TedRateLimitedException(wait);
  }

  String _firstError(Object? body) {
    final errors = body is Map<String, dynamic> ? body['errors'] : null;
    if (errors is List && errors.isNotEmpty && errors.first is Map) {
      return (errors.first as Map)['message']?.toString() ?? 'no data';
    }
    return 'no data';
  }
}
