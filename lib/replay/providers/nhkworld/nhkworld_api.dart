import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class NhkWorldRateLimitedException implements Exception {
  final Duration retryAfter;

  const NhkWorldRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Thin JSON access to the open "shows" API behind NHK WORLD-JAPAN on demand.
///
/// Lists are cached for a few minutes, the programme index for hours, and playback lookups never.
class NhkWorldApi {
  static const _host = 'api.nhkworld.jp';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _maxCachedPages = 120;

  /// Largest page the API accepts; one more is a 400.
  static const pageSize = 100;

  static const listTtl = Duration(minutes: 5);
  static const indexTtl = Duration(hours: 6);

  final MediaServerHttpClient _http;
  final String language;
  final DateTime Function() _clock;
  final LinkedHashMap<String, ({DateTime at, Map<String, dynamic> body})> _cache = LinkedHashMap();

  NhkWorldApi(this._http, {this.language = 'en', DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// One response. A [ttl] of zero always asks the server.
  Future<Map<String, dynamic>> json(String path, {Map<String, String>? query, Duration ttl = listTtl}) {
    final uri = Uri.https(_host, '/showsapi/v1/$language/$path', query);
    return _cached(uri, ttl);
  }

  /// The `items` of every page of a list, up to [maxPages] pages.
  Future<List<Map<String, dynamic>>> allItems(
    String path, {
    Map<String, String> query = const {},
    Duration ttl = listTtl,
    int maxPages = 20,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (var page = 0; page < maxPages; page++) {
      final body = await json(path, query: {...query, 'limit': '$pageSize', 'offset': '${page * pageSize}'}, ttl: ttl);
      final batch = (body['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
      items.addAll(batch);
      final total = ((body['pagination'] as Map?)?['total'] as num?)?.toInt() ?? items.length;
      if (batch.isEmpty || items.length >= total) break;
    }
    return items;
  }

  /// The `items` of one page.
  Future<List<Map<String, dynamic>>> items(String path, {Map<String, String>? query}) async {
    final body = await json(path, query: query);
    return (body['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  /// A programme, or null when the slug is unknown.
  Future<Map<String, dynamic>?> programme(String programId) async {
    try {
      return await json('video_programs/$programId');
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// One episode or clip by id, straight from the server so the stream address and expiry are current.
  Future<Map<String, dynamic>?> item({required bool clip, required String id, Duration ttl = Duration.zero}) async {
    final body = await json(clip ? 'video_clips' : 'video_episodes', query: {'ids': id}, ttl: ttl);
    final items = body['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().firstOrNull : null;
  }

  Future<Map<String, dynamic>> _cached(Uri uri, Duration ttl) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _clock().difference(hit.at) < ttl) return hit.body;
    final body = await _fetch(uri);
    if (ttl > Duration.zero) _remember(key, body);
    return body;
  }

  void _remember(String key, Map<String, dynamic> body) {
    _cache.remove(key);
    _cache[key] = (at: _clock(), body: body);
    while (_cache.length > _maxCachedPages) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) async {
    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw NhkWorldRateLimitedException(Duration(seconds: seconds));
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
