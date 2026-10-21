import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// A station site or Freecaster asked the client to slow down.
class TvLocalesRateLimitedException implements Exception {
  final Duration retryAfter;

  const TvLocalesRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Polite HTTP access to the station sites (HTML) and to the Freecaster player (JSON).
///
/// Site pages are cached for a few minutes, shared between concurrent callers and spaced out so that
/// paging through a show never bursts against a small regional server.
class TvLocalesApi {
  static const _embedBase = 'https://tvlocales-player.freecaster.com/embed';
  static const _headers = {
    'Accept': 'text/html,application/json;q=0.9',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _maxCachedPages = 80;

  final MediaServerHttpClient _http;
  final Duration minGap;
  final Duration pageTtl;
  final Map<String, ({DateTime at, Future<String> body})> _pages = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  TvLocalesApi(
    this._http, {
    this.minGap = const Duration(milliseconds: 300),
    this.pageTtl = const Duration(minutes: 5),
  });

  /// The HTML of a station page.
  Future<String> page(Uri uri) {
    final key = uri.toString();
    final hit = _pages[key];
    if (hit != null && DateTime.now().difference(hit.at) < pageTtl) return hit.body;
    final body = _fetchAndEvictOnFailure(key, uri);
    if (_pages.length >= _maxCachedPages) _pages.remove(_pages.keys.first);
    _pages[key] = (at: DateTime.now(), body: body);
    return body;
  }

  /// Player configuration of a video. Never cached: stream URLs belong to the moment of the request.
  Future<Map<String, dynamic>> embed(String videoId) async {
    final uri = Uri.parse('$_embedBase/$videoId.json');
    final response = await _http.get(uri.toString(), headers: _headers);
    _throwIfLimited(response);
    throwIfHttpError(response);
    final data = response.data;
    final json = data is String ? _decodeJson(data) : data;
    if (json is Map<String, dynamic>) return json;
    throw _unexpectedShape(uri, response.statusCode);
  }

  Future<String> _fetchAndEvictOnFailure(String key, Uri uri) async {
    try {
      return await _fetchPage(uri);
    } on Object {
      _pages.remove(key);
      rethrow;
    }
  }

  Future<String> _fetchPage(Uri uri) async {
    await _waitForSlot();
    final response = await _http.get(uri.toString(), headers: _headers);
    _throwIfLimited(response);
    throwIfHttpError(response);
    final data = response.data;
    if (data is String && data.isNotEmpty) return data;
    throw _unexpectedShape(uri, response.statusCode);
  }

  Future<void> _waitForSlot() async {
    final now = DateTime.now();
    final start = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = start.add(minGap);
    final wait = start.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  void _throwIfLimited(MediaServerResponse response) {
    if (response.statusCode != 429 && response.statusCode != 503) return;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
    throw TvLocalesRateLimitedException(Duration(seconds: seconds));
  }

  Object? _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  MediaServerHttpException _unexpectedShape(Uri uri, int status) => MediaServerHttpException(
    type: MediaServerHttpErrorType.unknown,
    statusCode: status,
    requestUri: uri,
    message: 'Unexpected response shape',
  );
}
