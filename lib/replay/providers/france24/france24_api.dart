import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import 'france24_models.dart';

/// The broadcaster refused a request because too many were made in a short time.
class France24RateLimitedException implements Exception {
  final Duration retryAfter;

  const France24RateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The application key was refused, which means France 24 rotated it and the app needs an update.
class France24TokenRejectedException implements Exception {
  const France24TokenRejectedException();

  @override
  String toString() => 'France 24 no longer accepts this app key';
}

/// The root document no longer lists the French edition, so no catalogue address is known.
class France24LayoutChangedException implements Exception {
  const France24LayoutChangedException();

  @override
  String toString() => 'France 24 changed the layout of its catalogue';
}

/// Catalogue addresses of one language edition, read from the root document.
class France24Guids {
  final String videos;
  final String programmes;
  final String latestEditions;
  final String programmeEditions;

  const France24Guids({
    required this.videos,
    required this.programmes,
    required this.latestEditions,
    required this.programmeEditions,
  });
}

/// Thin JSON access to the France 24 catalogue behind the official TV app.
///
/// Every list is a few hundred kilobytes to two megabytes and cannot be trimmed, so pages are parsed once,
/// cached as typed values and fetched at most one at a time with a pause between requests.
class France24Api {
  static const _host = 'apis.france24.com';
  static const _path = '/products/get_product';
  static const _rootGuid = '78dcf358-9333-4fb2-a035-7b91e9705b13';
  static const _language = 'FR';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  /// Public application key that France 24 ships inside its own apps. It identifies the app, not a user.
  static const applicationToken = '66b85dad-3ad5-40f3-ab32-2305fc2357ea';

  static const _ttl = Duration(minutes: 5);
  static const _cacheSize = 48;

  final MediaServerHttpClient _http;
  final Duration _minGap;
  final DateTime Function() _clock;
  final LinkedHashMap<String, ({DateTime at, Object value})> _cache = LinkedHashMap();
  final Map<String, Future<Object>> _inFlight = {};
  Future<France24Guids>? _guids;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;

  France24Api(this._http, {this._minGap = const Duration(milliseconds: 300), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  Future<France24Page<France24Programme>> programmes({int page = 1, String? nid}) async {
    final guids = await _addresses();
    return _page(guids.programmes, France24Programme.fromJson, page: page, nid: nid);
  }

  Future<France24Page<France24Edition>> latestEditions({int page = 1}) async {
    final guids = await _addresses();
    return _page(guids.latestEditions, France24Edition.fromJson, page: page);
  }

  /// The editions of one programme, newest first, 21 per page.
  Future<France24Page<France24Edition>> editions(String programmeNid, {int page = 1}) async {
    final guids = await _addresses();
    return _page(guids.programmeEditions, France24Edition.fromJson, page: page, nid: programmeNid);
  }

  Future<France24Page<France24Video>> videos({int page = 1, String? nid}) async {
    final guids = await _addresses();
    return _page(guids.videos, France24Video.fromJson, page: page, nid: nid);
  }

  void clearCache() {
    _cache.clear();
    _guids = null;
  }

  Future<France24Guids> _addresses() async {
    final pending = _guids ??= _loadAddresses();
    try {
      return await pending;
    } catch (_) {
      _guids = null;
      rethrow;
    }
  }

  Future<France24Guids> _loadAddresses() async {
    final result = await _cached(_uri(_rootGuid), (r) => r);
    final languages = (result['list'] as Map?)?['languages'];
    final edition = languages is List
        ? languages.whereType<Map<String, dynamic>>().where((l) => l['code'] == _language).firstOrNull
        : null;
    final tv = edition?['tv'];
    final shows = tv is Map ? tv['shows'] : null;
    String? guid(Object? entry) => entry is Map ? entry['guid'] as String? : null;
    final videos = guid(tv is Map ? tv['videos'] : null);
    final programmes = guid(shows is Map ? shows['shows_all'] : null);
    final latest = guid(shows is Map ? shows['shows_last_edition'] : null);
    final editions = guid(shows is Map ? shows['show_editions'] : null);
    if (videos == null || programmes == null || latest == null || editions == null) {
      throw const France24LayoutChangedException();
    }
    return France24Guids(videos: videos, programmes: programmes, latestEditions: latest, programmeEditions: editions);
  }

  Future<France24Page<T>> _page<T>(
    String guid,
    T? Function(Map<String, dynamic>) parse, {
    required int page,
    String? nid,
  }) => _cached(_uri(guid, page: page, nid: nid), (result) {
    final list = result['list'];
    if (list is! List) throw const France24LayoutChangedException();
    return France24Page<T>(
      items: [for (final raw in list.whereType<Map<String, dynamic>>()) ?parse(raw)],
      total: (result['nb_total_item'] as num?)?.toInt() ?? list.length,
      page: (result['current_page'] as num?)?.toInt() ?? page,
      lastPage: (result['last_page'] as num?)?.toInt() ?? 1,
    );
  });

  Uri _uri(String guid, {int page = 1, String? nid}) => Uri.https(_host, '$_path/$guid', {
    'token_application': applicationToken,
    if (page > 1) 'page': '$page',
    'nid': ?nid,
  });

  Future<T> _cached<T extends Object>(Uri uri, T Function(Map<String, dynamic> result) parse) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _clock().difference(hit.at) < _ttl) return hit.value as T;
    final pending = _inFlight[key];
    if (pending != null) return await pending as T;

    final request = _fetch(uri).then<Object>(parse);
    _inFlight[key] = request;
    try {
      final value = await request;
      _remember(key, value);
      return value as T;
    } finally {
      _inFlight.removeWhere((k, _) => k == key);
    }
  }

  void _remember(String key, Object value) {
    _cache.remove(key);
    _cache[key] = (at: _clock(), value: value);
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) async {
    final blocked = _blockedUntil;
    if (blocked != null && blocked.isAfter(_clock())) throw France24RateLimitedException(blocked.difference(_clock()));
    await _waitForSlot();

    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _blockedUntil = _clock().add(Duration(seconds: seconds));
      throw France24RateLimitedException(Duration(seconds: seconds));
    }
    if (response.statusCode == 401) throw const France24TokenRejectedException();
    throwIfHttpError(response);
    final data = response.data;
    final result = data is Map<String, dynamic> ? data['result'] : null;
    if (result is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Unexpected response shape',
      );
    }
    return result;
  }

  /// Reserves the next request slot synchronously so concurrent callers queue up instead of bursting.
  Future<void> _waitForSlot() async {
    final now = _clock();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(_minGap);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
}
