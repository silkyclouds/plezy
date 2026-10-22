import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// TVP VOD refused a request because too many were made in a short time.
class TvpVodRateLimitedException implements Exception {
  final Duration retryAfter;

  const TvpVodRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A playlist answer kept as it came, because the refusal reasons live in the body of a 403.
class TvpPlaylistReply {
  final int statusCode;
  final Object? body;

  const TvpPlaylistReply(this.statusCode, this.body);
}

/// Thin JSON access to the open catalogue and playlist endpoints of vod.tvp.pl.
class TvpVodApi {
  static const _host = 'vod.tvp.pl';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _cacheTtl = Duration(minutes: 5);
  static const _cacheLimit = 400;
  static const _parallelRequests = 4;

  final MediaServerHttpClient _http;
  final Map<String, ({DateTime at, Object body})> _cache = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  TvpVodApi(this._http);

  /// A catalogue response under `/api/products/`. The decoded JSON is a map or a list, cached for a few minutes.
  Future<Object> products(String path, {Map<String, Object>? query}) async {
    final uri = _uri('products/$path', query);
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) return hit.body;
    final body = await _read(uri);
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  /// The playlist of a playable product. Never cached: the stream address carries a token for the day.
  Future<TvpPlaylistReply> playlist(String id) async {
    final response = await _get(_uri('products/$id/videos/playlist', {'videoType': 'MOVIE'}));
    _throwIfLimited(response);
    return TvpPlaylistReply(response.statusCode, _decode(response.data));
  }

  Uri _uri(String path, Map<String, Object>? query) => Uri(
    scheme: 'https',
    host: _host,
    path: '/api/$path',
    queryParameters: {'lang': 'pl', 'platform': 'BROWSER', ...?query},
  );

  Future<Object> _read(Uri uri) async {
    final response = await _get(uri);
    _throwIfLimited(response);
    throwIfHttpError(response);
    final data = _decode(response.data);
    if (data is Map<String, dynamic>) return data;
    if (data is List) return data;
    throw MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      statusCode: response.statusCode,
      requestUri: uri,
      message: 'Unexpected response shape',
    );
  }

  void _throwIfLimited(MediaServerResponse response) {
    if (response.statusCode != 429) return;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
    throw TvpVodRateLimitedException(Duration(seconds: seconds));
  }

  Object? _decode(Object? data) {
    if (data is! String) return data;
    try {
      return jsonDecode(data);
    } on FormatException {
      return null;
    }
  }

  /// At most [_parallelRequests] requests are in flight, so a list of forecasts cannot flood the site.
  Future<MediaServerResponse> _get(Uri uri) async {
    while (_active >= _parallelRequests) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _active++;
    try {
      return await _http.get(uri.toString(), headers: _headers);
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}
