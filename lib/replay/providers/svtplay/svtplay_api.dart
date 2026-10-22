import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class SvtPlayRateLimitedException implements Exception {
  final Duration retryAfter;

  const SvtPlayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A GraphQL answer with errors and no data. The server reports validation problems with HTTP 200.
class SvtPlayQueryException implements Exception {
  final String message;

  const SvtPlayQueryException(this.message);

  @override
  String toString() => 'SVT Play query failed: $message';
}

/// Access to the SVT Play catalogue (GraphQL) and its video API.
class SvtPlayApi {
  static const _graphqlUrl = 'https://contento.svt.se/graphql';
  static const _videoUrl = 'https://api.svt.se/videoplayer-api/video';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  /// Catalogue answers that change slowly. Details and search are cached shorter.
  static const listTtl = Duration(minutes: 15);
  static const detailsTtl = Duration(minutes: 5);
  static const wholeCatalogueTtl = Duration(hours: 12);
  static const _maxCached = 120;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> data})> _cache = {};

  SvtPlayApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Runs a catalogue query and returns its `data` object, cached for [ttl].
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, Object?> variables = const {},
    Duration ttl = listTtl,
  }) async {
    final key = '$document|${jsonEncode(variables)}';
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.data;

    final response = await _http.post(
      _graphqlUrl,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': document, 'variables': variables}),
    );
    _checkStatus(response);
    final data = _dataOf(response);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), data: data);
    return data;
  }

  /// Playback information for a video id. Never cached: rights and windows are read at the moment of play.
  Future<Map<String, dynamic>> video(String svtId) async {
    final response = await _http.get('$_videoUrl/${Uri.encodeComponent(svtId)}', headers: _headers);
    _checkStatus(response);
    final body = response.data;
    if (body is! Map<String, dynamic>) throw _unexpectedShape(response);
    return body;
  }

  /// Whether the CDN serves the manifest to this viewer. Sweden-only titles answer 403 outside Sweden.
  Future<bool> manifestReachable(Uri manifest) async {
    final response = await _http.get(manifest.toString(), headers: {'User-Agent': _headers['User-Agent']!});
    if (response.statusCode == 401 || response.statusCode == 403) return false;
    _checkStatus(response);
    return true;
  }

  void _checkStatus(MediaServerResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw SvtPlayRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
  }

  Map<String, dynamic> _dataOf(MediaServerResponse response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) throw _unexpectedShape(response);
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    final errors = body['errors'];
    final first = errors is List && errors.isNotEmpty ? errors.first : null;
    final message = first is Map ? first['message'] : null;
    throw SvtPlayQueryException('${message ?? 'no data in the response'}');
  }

  MediaServerHttpException _unexpectedShape(MediaServerResponse response) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: response.statusCode,
    requestUri: response.requestUri,
    message: 'Unexpected response shape',
  );
}
