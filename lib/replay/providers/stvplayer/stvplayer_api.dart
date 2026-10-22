import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class StvPlayerRateLimitedException implements Exception {
  final Duration retryAfter;

  const StvPlayerRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// One page of a catalogue list and the size of the whole list.
typedef StvPage = ({List<Map<String, dynamic>> items, int total});

const stvPlayerUserAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
const stvPlayerHeaders = {'Accept': 'application/json', 'User-Agent': stvPlayerUserAgent};

/// Read access to STV Player's open catalogue: programmes, episodes, categories and news clips.
///
/// No account or key is needed. Responses are cached for a few minutes, the programme list for a day.
class StvPlayerApi {
  static const _base = 'https://player.api.stv.tv/v1';
  static const _shortTtl = Duration(minutes: 5);
  static const _programmeListTtl = Duration(days: 1);
  static const _maxCached = 40;

  /// The server clamps a page to these sizes, and a page can come back a row short, so paging counts offsets.
  static const _programmePageSize = 299;
  static const _episodePageSize = 400;
  static const _maxPages = 4;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  ({DateTime at, List<Map<String, dynamic>> items})? _allProgrammes;

  StvPlayerApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<List<Map<String, dynamic>>> categories() async => _items(await _get('/categories'));

  /// One page of programmes. [query] may hold `category`, `orderBy` and `startLetter`.
  Future<StvPage> programmes({Map<String, String> query = const {}, required int limit, int offset = 0}) =>
      _page('/programmes', query, limit, offset);

  /// One page of episodes. [query] may hold `orderBy`, `programme.guid` and `playerSeries.guid`.
  Future<StvPage> episodes({Map<String, String> query = const {}, required int limit, int offset = 0}) =>
      _page('/episodes', query, limit, offset);

  /// One page of the news clips feed.
  Future<StvPage> clips({required int limit, int offset = 0}) =>
      _page('/shortform', const {'programme_guid': 'stv-news-clips'}, limit, offset);

  Future<Map<String, dynamic>?> programme(String guid) => _one('/programmes/${Uri.encodeComponent(guid)}');

  /// The episode with this numeric id. [fresh] skips the cache, for the moment of playing.
  Future<Map<String, dynamic>?> episode(String id, {bool fresh = false}) =>
      _one('/episodes/${Uri.encodeComponent(id)}', fresh: fresh);

  Future<Map<String, dynamic>?> clip(String id, {bool fresh = false}) =>
      _one('/shortform/${Uri.encodeComponent(id)}', fresh: fresh);

  /// Every episode matching [query], oldest page first, up to a few thousand.
  Future<List<Map<String, dynamic>>> allEpisodes(Map<String, String> query) async {
    final collected = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final chunk = await episodes(query: query, limit: _episodePageSize, offset: page * _episodePageSize);
      collected.addAll(chunk.items);
      if (chunk.items.isEmpty || (page + 1) * _episodePageSize >= chunk.total) break;
    }
    return collected;
  }

  /// The whole programme list, once per day. Search runs over it because the server has no usable search.
  Future<List<Map<String, dynamic>>> allProgrammes() async {
    final hit = _allProgrammes;
    if (hit != null && _now().difference(hit.at) < _programmeListTtl) return hit.items;

    final seen = <String>{};
    final collected = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final chunk = await programmes(
        query: const {'orderBy': 'name'},
        limit: _programmePageSize,
        offset: page * _programmePageSize,
      );
      for (final programme in chunk.items) {
        if (seen.add(programme['guid'] as String)) collected.add(programme);
      }
      if (chunk.items.isEmpty || (page + 1) * _programmePageSize >= chunk.total) break;
    }
    _allProgrammes = (at: _now(), items: collected);
    return collected;
  }

  Future<StvPage> _page(String path, Map<String, String> query, int limit, int offset) async {
    final body = await _get(path, query: {...query, 'limit': '$limit', 'offset': '$offset'});
    return (items: _items(body), total: (body['totalResults'] as num?)?.toInt() ?? 0);
  }

  Future<Map<String, dynamic>?> _one(String path, {bool fresh = false}) async {
    final body = await _get(path, fresh: fresh);
    final result = body['results'];
    return result is Map<String, dynamic> ? result : null;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> body) {
    final results = body['results'];
    return results is List ? results.whereType<Map<String, dynamic>>().toList() : const [];
  }

  /// The JSON body of a GET. A 404 is an empty body: the catalogue answers it for ids it no longer has.
  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query, bool fresh = false}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final key = uri.toString();
    final hit = _cache[key];
    if (!fresh && hit != null && _now().difference(hit.at) < _shortTtl) return hit.body;

    final response = await _http.get(key, headers: stvPlayerHeaders);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw StvPlayerRateLimitedException(Duration(seconds: seconds));
    }
    if (response.statusCode == 404) return const {};
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
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), body: data);
    return data;
  }
}
