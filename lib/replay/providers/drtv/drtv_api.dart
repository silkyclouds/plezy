import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import 'drtv_session.dart';

/// DR asked for fewer requests. [retryAfter] is how long it wants us to wait.
class DrtvRateLimitedException implements Exception {
  final Duration retryAfter;

  const DrtvRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A decoded JSON object.
typedef DrtvJson = Map<String, dynamic>;

/// Thin JSON access to DR's catalogue ("Massive") and its stream resolver.
///
/// Requests are spaced out, catalogue answers are kept for a few minutes, and a refused token is renewed once.
class DrtvApi {
  static const origin = 'https://prod95-cdn.dr-massive.com/api';
  static const _defaults = {
    'device': 'web_browser',
    'ff': 'idp,ldp,rpt',
    'lang': 'da',
    'sub': 'Anonymous',
    'segments': 'drtv,optedout',
  };
  static const _headers = {'Accept': 'application/json', 'Accept-Encoding': 'identity', 'User-Agent': drtvUserAgent};
  static const _cacheLimit = 300;

  final MediaServerHttpClient _http;
  final Duration _minInterval;
  final Duration _ttl;
  final DateTime Function() _now;
  final DrtvSession _session;
  final String _searchSession;
  final Map<String, ({DateTime at, Object? body})> _cache = {};

  Future<void> _turn = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  DrtvApi(
    this._http, {
    this._minInterval = const Duration(milliseconds: 150),
    Duration cacheTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
    String Function()? newId,
  }) : _ttl = cacheTtl,
       _now = clock ?? DateTime.now,
       _searchSession = (newId ?? const Uuid().v4)(),
       _session = DrtvSession(_http, newDeviceId: newId ?? const Uuid().v4, clock: clock ?? DateTime.now);

  /// A page of the site (home, category, show, season). Null when DR has no such page. [expand] asks for the full
  /// detail of the opened show or season.
  Future<DrtvJson?> page(String path, {int listPageSize = 50, int? maxListPrefetch, bool expand = false}) =>
      _object('/page', {
        'path': path,
        if (expand) 'item_detail_expand': 'all',
        'list_page_size': '$listPageSize',
        'max_list_prefetch': ?maxListPrefetch?.toString(),
      });

  /// One page of a list, counted from 1. [param] selects the slice of a parametrised list, such as one A-Z letter.
  Future<DrtvJson?> list(String listId, {int page = 1, int pageSize = 24, String? param}) =>
      _object('/lists/$listId', {'page_size': '$pageSize', 'page': '$page', 'param': ?param});

  /// The continuation DR gives as a relative link.
  Future<DrtvJson?> next(String relativeUrl) => _object(null, const {}, absolute: Uri.parse('$origin$relativeUrl'));

  Future<DrtvJson?> item(String id) => _object('/items/$id', {'item_detail_expand': 'all'});

  Future<DrtvJson> search(String term) async =>
      await _object('/v2/search', {'term': term, 'sessionId': _searchSession, 'group': 'true'}) ?? const {};

  /// Stream descriptions of a playable item, or null when DR no longer has it. Never cached: rights change.
  Future<List<DrtvJson>?> videos(String id) async {
    final body = await _get(
      Uri.parse(
        '$origin/account/items/$id/videos',
      ).replace(queryParameters: {..._defaults, 'delivery': 'stream', 'resolution': 'HD-1080'}),
      cache: false,
    );
    return body is List ? body.whereType<DrtvJson>().toList() : (body == null ? null : const []);
  }

  /// The status the CDN answers for a manifest. Stream URLs carry their own rights and need no catalogue token.
  Future<int> manifestStatus(Uri url) async {
    final response = await _http.get(url.toString(), headers: const {'User-Agent': drtvUserAgent});
    return response.statusCode;
  }

  Future<DrtvJson?> _object(String? path, Map<String, String> query, {Uri? absolute}) async {
    final uri = absolute ?? Uri.parse('$origin$path').replace(queryParameters: {..._defaults, ...query});
    final body = await _get(uri);
    return body is DrtvJson ? body : null;
  }

  Future<Object?> _get(Uri uri, {bool cache = true}) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (cache && hit != null && _now().difference(hit.at) < _ttl) return hit.body;
    final body = await _fetch(uri);
    if (cache && body != null) _remember(key, body);
    return body;
  }

  void _remember(String key, Object body) {
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), body: body);
  }

  Future<Object?> _fetch(Uri uri, {bool renewToken = true}) async {
    if (_now().isBefore(_pausedUntil)) throw DrtvRateLimitedException(_pausedUntil.difference(_now()));
    await _waitForTurn();
    final token = await _session.token();
    final response = await _http.get(uri.toString(), headers: {..._headers, 'Authorization': 'Bearer $token'});

    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _pausedUntil = _now().add(Duration(seconds: seconds));
      throw DrtvRateLimitedException(Duration(seconds: seconds));
    }
    if ((response.statusCode == 401 || response.statusCode == 403) && renewToken) {
      _session.invalidate();
      return _fetch(uri, renewToken: false);
    }
    if (response.statusCode == 404) return null;
    throwIfHttpError(response);
    final data = response.data;
    if (data is! DrtvJson && data is! List) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Unexpected response shape',
      );
    }
    return data;
  }

  Future<void> _waitForTurn() {
    final previous = _turn;
    final mine = Completer<void>();
    _turn = mine.future;
    return previous.then((_) async {
      final wait = _minInterval - _now().difference(_lastRequest);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastRequest = _now();
      mine.complete();
    });
  }
}
