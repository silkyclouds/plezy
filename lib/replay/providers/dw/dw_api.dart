import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// DW refused a request because too many were made in a short time.
class DwRateLimitedException implements Exception {
  final Duration retryAfter;

  const DwRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// JSON access to the endpoints DW's own web app uses: the content graph and the search engine behind the site.
class DwApi {
  static const _graphBase = 'https://www.dw.com/graph-api/en/';
  static const _searchUrl = 'https://webapi.dw.com/searchapi/api/as/v1/engines/english-nest/search';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _graphTtl = Duration(minutes: 5);
  static const _searchTtl = Duration(minutes: 2);
  static const _cacheLimit = 120;

  final MediaServerHttpClient _http;
  final DateTime Function() _clock;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};

  DwApi(this._http, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// A content-graph document such as `programs-overview` or `content/video/{id}`, or null when DW answers 404.
  /// A video, a programme and a page are told apart by the type segment, which must match the id.
  Future<Map<String, dynamic>?> graph(String path) async {
    final uri = Uri.parse('$_graphBase$path');
    final key = uri.toString();
    final hit = _fresh(key, _graphTtl);
    if (hit != null) return hit;
    final response = await _http.get(key, headers: _headers);
    if (response.statusCode == 404) return null;
    return _store(key, _json(response, uri));
  }

  /// One search-engine request. Answers are cached for a couple of minutes; the request body is the cache key.
  Future<Map<String, dynamic>> search(Map<String, dynamic> request) async {
    final key = 'search ${jsonEncode(request)}';
    final hit = _fresh(key, _searchTtl);
    if (hit != null) return hit;
    final uri = Uri.parse(_searchUrl);
    final response = await _http.post(_searchUrl, headers: _headers, body: request);
    return _store(key, _json(response, uri));
  }

  void clearCache() => _cache.clear();

  Map<String, dynamic>? _fresh(String key, Duration ttl) {
    final hit = _cache[key];
    return hit != null && _clock().difference(hit.at) < ttl ? hit.body : null;
  }

  Map<String, dynamic> _store(String key, Map<String, dynamic> body) {
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _clock(), body: body);
    return body;
  }

  Map<String, dynamic> _json(MediaServerResponse response, Uri uri) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw DwRateLimitedException(Duration(seconds: seconds));
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
