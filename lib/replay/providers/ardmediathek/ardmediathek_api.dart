import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The gateway refused a request because too many were made in a short time.
class ArdMediathekRateLimitedException implements Exception {
  final Duration retryAfter;

  const ArdMediathekRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Thin JSON access to the ARD Mediathek page gateway.
///
/// Every gateway path takes a partner segment but answers the same for any of them, so requests built from an
/// id use `ard`. Requests are spaced out, and after a 429 nothing is sent until the Retry-After delay has passed.
class ArdMediathekApi {
  static const _base = 'https://api.ardmediathek.de/page-gateway';
  static const _partner = 'ard';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _pageTtl = Duration(minutes: 3);
  static const _probeTimeout = Duration(seconds: 8);
  static const _cacheLimit = 80;

  final MediaServerHttpClient _http;
  final Duration minSpacing;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  ArdMediathekApi(this._http, {this.minSpacing = const Duration(milliseconds: 80)});

  /// The landing page of a channel (`ard` is the whole Mediathek), with the first cards of every row inlined.
  Future<Map<String, dynamic>> home({String partner = _partner}) =>
      _cached(_pages('$partner/home', {'embedded': 'true'}));

  /// A category page by slug, such as `filme`.
  Future<Map<String, dynamic>> editorial(String slug) =>
      _cached(_pages('$_partner/editorial/${Uri.encodeComponent(slug)}', {'embedded': 'true'}));

  /// A show page. Cards are not inlined: the episode list comes from [showEpisodes].
  Future<Map<String, dynamic>> grouping(String id) =>
      _cached(_pages('$_partner/grouping/${Uri.encodeComponent(id)}', {'embedded': 'false'}));

  /// A video page with its media collection. Never cached: rights and availability change with the moment.
  Future<Map<String, dynamic>> item(String id) =>
      _fetch(_pages('$_partner/item/${Uri.encodeComponent(id)}', {'devicetype': 'pc', 'embedded': 'false'}));

  /// Episodes of a show: one numbered [season], or every video when it is null.
  Future<Map<String, dynamic>> showEpisodes(String showId, {int? season, int page = 0, int size = 100}) {
    return _cached(
      Uri.parse('$_base/widgets/$_partner/asset/${Uri.encodeComponent(showId)}').replace(
        queryParameters: {
          'pageNumber': '$page',
          'pageSize': '$size',
          'embedded': 'true',
          'seasoned': season == null ? 'false' : 'true',
          'seasonNumber': season?.toString() ?? '',
          'withAudiodescription': 'false',
          'withOriginalWithSubtitle': 'false',
          'withOriginalversion': 'false',
          'single': 'false',
        },
      ),
    );
  }

  /// One row of a page by the path the gateway gave for it, such as `ard/editorials/ID`.
  Future<Map<String, dynamic>> widget(String path, {int page = 0, int size = 48}) => _cached(
    Uri.parse(
      '$_base/widgets/$path',
    ).replace(queryParameters: {'pageNumber': '$page', 'pageSize': '$size', 'embedded': 'true'}),
  );

  Future<Map<String, dynamic>> searchShows(String query, {int page = 0, int size = 24}) =>
      _search('grouping', query, page, size);

  Future<Map<String, dynamic>> searchVideos(String query, {int page = 0, int size = 24}) =>
      _search('vod', query, page, size);

  /// The HTTP status a stream URL answers with, or null when it could not be reached.
  ///
  /// Used to learn whether a CDN accepts the viewer's country. One byte is requested.
  Future<int?> streamStatus(Uri url) async {
    try {
      final response = await _http.get(
        url.toString(),
        headers: {..._headers, 'Range': 'bytes=0-0'},
        timeout: _probeTimeout,
      );
      return response.statusCode;
    } on MediaServerHttpException {
      return null;
    }
  }

  Future<Map<String, dynamic>> _search(String kind, String query, int page, int size) => _cached(
    Uri.parse(
      '$_base/widgets/$_partner/search/$kind',
    ).replace(queryParameters: {'searchString': query, 'pageNumber': '$page', 'pageSize': '$size'}),
  );

  Uri _pages(String path, Map<String, String> query) => Uri.parse('$_base/pages/$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _cached(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _pageTtl) return hit.body;
    final body = await _fetch(uri);
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) async {
    final blocked = _blockedUntil.difference(DateTime.now());
    if (blocked > Duration.zero) throw ArdMediathekRateLimitedException(blocked);
    await _waitForSlot();
    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
      throw ArdMediathekRateLimitedException(Duration(seconds: seconds));
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

  Future<void> _waitForSlot() async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(minSpacing);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
}
