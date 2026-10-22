import 'dart:async';

import '../../../utils/media_server_http_client.dart';
import 'lrt_article.dart';
import 'lrt_feed.dart';
import 'lrt_index.dart';
import 'lrt_models.dart';
import 'lrt_refs.dart';
import 'lrt_search.dart';
import 'lrt_show_page.dart';

/// The site asked for fewer requests. Further calls fail at once until [retryAfter] has passed.
class LrtRateLimitedException implements Exception {
  final Duration retryAfter;

  const LrtRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// How a stream playlist answered a probe.
typedef LrtManifestProbe = ({int status, String body});

/// Access to lrt.lt: RSS feeds, the programme pages, the search API and the stream lookup.
///
/// Catalogue requests are spaced by [minInterval] and cached. Stream lookups and probes are never cached, because
/// rights change with the moment, and are not spaced, since one lookup answers one press of play.
class LrtApi {
  static const _headers = {
    'Accept': '*/*',
    'Accept-Language': 'lt',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  static const feedTtl = Duration(minutes: 5);
  static const pageTtl = Duration(minutes: 10);
  static const indexTtl = Duration(hours: 24);
  static const _maxCached = 80;

  final MediaServerHttpClient _http;
  final Duration minInterval;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Object value})> _cache = {};
  Future<void> _turn = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;

  LrtApi(this._http, {this.minInterval = const Duration(milliseconds: 200), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Recordings of a feed. [path] is relative to `/mediateka`: empty for the whole site, `/filmai`, `/video/{slug}`.
  Future<List<LrtRecording>> feed(String path) =>
      _cached('feed|$path', feedTtl, () async => parseLrtFeed(await _text('$lrtOrigin/mediateka$path?rss')));

  /// A programme page, or null when the site has no such programme or the page carries none.
  Future<LrtShowPage?> showPage(String slug) async {
    final key = 'show|$slug';
    final hit = _fresh<LrtShowPage>(key, pageTtl);
    if (hit != null) return hit;
    final html = await _textOrNull('$lrtOrigin/mediateka/video/${Uri.encodeComponent(slug)}');
    final page = parseLrtShowPage(html, slug: slug);
    if (page != null) _store(key, page);
    return page;
  }

  /// Every TV programme of the site, alphabetically. About a megabyte of HTML, hence the long cache. An empty answer
  /// is not kept, so a page that failed to parse is asked for again.
  Future<List<LrtProgramme>> programmeIndex() async {
    final hit = _fresh<List<LrtProgramme>>('index', indexTtl);
    if (hit != null) return hit;
    final programmes = parseLrtProgrammeIndex(await _text('$lrtOrigin/mediateka/tv-laidos'));
    if (programmes.isNotEmpty) _store('index', programmes);
    return programmes;
  }

  /// One page of video search results (1-based).
  Future<LrtSearchPage> search(String query, {int page = 1}) => _cached(
    'search|$query|$page',
    feedTtl,
    () async => parseLrtSearch(
      await _json(
        Uri.parse('$lrtOrigin/api/json/search').replace(queryParameters: {'q': query, 'type': '3', 'page': '$page'}),
      ),
    ),
  );

  /// A recording's metadata record, or null when the site has none.
  Future<LrtRecording?> article(String postId) async {
    final key = 'article|$postId';
    final hit = _fresh<LrtRecording>(key, feedTtl);
    if (hit != null) return hit;
    final body = await _jsonOrNull(Uri.parse('$lrtOrigin/rest-api/articles/mediateka/$postId/$_slug'));
    final recording = parseLrtArticle(body, postId: postId);
    if (recording != null) _store(key, recording);
    return recording;
  }

  /// The stream lookup for a recording. The answer is returned as received; see `parseLrtMediaInfo`.
  Future<Object?> mediaInfo(String postId) async {
    final uri = Uri.parse(
      '$lrtOrigin/servisai/stream_url/vod/media_info/',
    ).replace(queryParameters: {'url': '/mediateka/irasas/$postId/$_slug'});
    return _jsonOrNull(uri, spaced: false);
  }

  /// Fetches a stream playlist to learn whether the file is still there. Expired recordings keep their lookup but
  /// their files answer 404.
  Future<LrtManifestProbe> probeManifest(Uri url) async {
    _checkBlocked();
    final response = await _http.get(url.toString(), headers: {'User-Agent': _headers['User-Agent']!});
    _checkRateLimit(response);
    final data = response.data;
    return (status: response.statusCode, body: data is String ? data : '');
  }

  // The lookup and the metadata record need a slug in the path but ignore its value.
  static const _slug = 'x';

  Future<T> _cached<T extends Object>(String key, Duration ttl, Future<T> Function() load) async {
    final hit = _fresh<T>(key, ttl);
    if (hit != null) return hit;
    final value = await load();
    _store(key, value);
    return value;
  }

  T? _fresh<T extends Object>(String key, Duration ttl) {
    final hit = _cache[key];
    if (hit == null || _now().difference(hit.at) >= ttl) return null;
    final value = hit.value;
    return value is T ? value : null;
  }

  void _store(String key, Object value) {
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), value: value);
  }

  Future<String> _text(String url) async => await _textOrNull(url) ?? '';

  Future<String?> _textOrNull(String url) async {
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    throwIfHttpError(response);
    final data = response.data;
    return data is String ? data : null;
  }

  Future<Object?> _json(Uri uri) async {
    final response = await _get(uri.toString());
    throwIfHttpError(response);
    return response.data;
  }

  Future<Object?> _jsonOrNull(Uri uri, {bool spaced = true}) async {
    final response = await _get(uri.toString(), spaced: spaced);
    if (response.statusCode == 404) return null;
    throwIfHttpError(response);
    return response.data;
  }

  Future<MediaServerResponse> _get(String url, {bool spaced = true}) async {
    _checkBlocked();
    if (spaced) await _waitMyTurn();
    final response = await _http.get(url, headers: _headers);
    _checkRateLimit(response);
    return response;
  }

  void _checkBlocked() {
    final until = _blockedUntil;
    if (until == null) return;
    final left = until.difference(_now());
    if (left > Duration.zero) throw LrtRateLimitedException(left);
    _blockedUntil = null;
  }

  void _checkRateLimit(MediaServerResponse response) {
    if (response.statusCode != 429) return;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
    final wait = Duration(seconds: seconds);
    _blockedUntil = _now().add(wait);
    throw LrtRateLimitedException(wait);
  }

  /// Queues the caller behind earlier catalogue requests and waits until [minInterval] has passed since the last one.
  Future<void> _waitMyTurn() {
    final previous = _turn;
    final mine = Completer<void>();
    _turn = mine.future;
    return previous.then((_) async {
      final wait = minInterval - _now().difference(_lastRequest);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastRequest = _now();
      mine.complete();
    });
  }
}
