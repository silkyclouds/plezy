import 'dart:async';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class Tf1RateLimitedException implements Exception {
  final Duration retryAfter;

  const Tf1RateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The gateway answered 200 but could not run the query at all.
class Tf1GraphqlException implements Exception {
  final List<String> messages;

  const Tf1GraphqlException(this.messages);

  @override
  String toString() => 'TF1+ query failed: ${messages.join('; ')}';
}

/// Persisted query ids of the catalogue gateway. The short ids are the long-lived ones; the hashed ids of
/// the web app change with every site release and are not used.
abstract final class Tf1Operation {
  static const programs = '483ce0f';
  static const programVideos = 'a6f9cf0e';
  static const seasonEpisodes = '76bc5c35edb166fa637a6c6686cb05c7140d2a8b';
  static const searchPrograms = 'e78b188';
  static const searchVideos = 'b2dc9439';
  static const programDetail = '379fec96081ab1a2';
}

/// Request spacing, cache lifetime and the longest Retry-After worth waiting for.
class Tf1Pacing {
  final Duration minInterval;
  final Duration cacheTtl;
  final Duration maxRetryWait;

  const Tf1Pacing({
    this.minInterval = const Duration(milliseconds: 250),
    this.cacheTtl = const Duration(minutes: 5),
    this.maxRetryWait = const Duration(seconds: 10),
  });

  /// No pauses, for tests.
  static const none = Tf1Pacing(minInterval: Duration.zero, maxRetryWait: Duration.zero);
}

/// Thin JSON access to TF1+'s anonymous catalogue gateway and its playback resolver.
class Tf1Api {
  static const _webGateway = 'https://www.tf1.fr/graphql/web';
  static const _smartTvGateway = 'https://smart-tv.tf1.fr/catalog/fr-fr/smarttv';
  static const _mediaInfo = 'https://mediainfo.tf1.fr/mediainfocombo';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _mediaInfoQuery = {
    'context': 'MYTF1',
    'pver': '5010000',
    'platform': 'web',
    'device': 'desktop',
    'os': 'linux',
    'osVersion': 'unknown',
    'topDomain': 'https://www.tf1.fr',
    'playerVersion': '5.19.0',
    'productName': 'mytf1',
    'productVersion': '3.22.0',
  };
  static const _context = {'persona': 'PERSONA_2', 'application': 'WEB', 'device': 'DESKTOP', 'os': 'WINDOWS'};

  final MediaServerHttpClient _http;
  final Tf1Pacing pacing;
  final Future<void> Function(Duration) _delay;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  Tf1Api(this._http, {this.pacing = const Tf1Pacing(), Future<void> Function(Duration)? delay})
    : _delay = delay ?? Future<void>.delayed;

  /// The client every call goes through, shared with the sign-in calls of the same provider.
  MediaServerHttpClient get http => _http;

  /// One page of programmes. [filter] holds `channel`, `categorySlug`, `category` or `startWith`.
  Future<Map<String, dynamic>?> programs(Map<String, String> filter, {int page = 0, int limit = 20}) async {
    final body = await _graphql(Tf1Operation.programs, {
      'context': _context,
      'filter': {'channel': '', ...filter},
      'offset': page,
      'limit': limit,
    });
    return _entity(body, 'programs');
  }

  Future<Map<String, dynamic>?> searchPrograms(String query, {int limit = 20}) async => _entity(
    await _graphql(Tf1Operation.searchPrograms, {'query': query, 'offset': 0, 'limit': limit}),
    'searchPrograms',
  );

  Future<Map<String, dynamic>?> searchVideos(String query, {int limit = 20}) async =>
      _entity(await _graphql(Tf1Operation.searchVideos, {'query': query, 'offset': 0, 'limit': limit}), 'searchVideos');

  /// A programme with a page of its videos of one [type] (`REPLAY`, `EXTRACT` or `BONUS`), newest first.
  Future<Map<String, dynamic>?> programVideos(
    String slug, {
    int page = 0,
    int limit = 20,
    String type = 'REPLAY',
  }) async {
    final body = await _graphql(Tf1Operation.programVideos, {
      'programSlug': slug,
      'offset': page,
      'limit': limit,
      'sort': {'type': 'DATE', 'order': 'DESC'},
      'types': [type],
    });
    return _entity(body, 'programBySlug');
  }

  /// A programme's header, cast and season lists. Needs the programme id, which the slug lookup returns.
  Future<Map<String, dynamic>?> programDetail(String programId) async {
    final body = await _graphql(Tf1Operation.programDetail, {'programId': programId}, gateway: _smartTvGateway);
    return _entity(body, 'programById');
  }

  /// One page of the episodes of a season list, in broadcast order.
  Future<Map<String, dynamic>?> seasonEpisodes(String slug, String listId, {int page = 0, int limit = 100}) async {
    final body = await _graphql(Tf1Operation.seasonEpisodes, {
      'programSlug': slug,
      'listId': listId,
      'offset': page,
      'limit': limit,
    });
    final sections = _entity(body, 'programBySlug')?['editorialSections'];
    if (sections is! List || sections.isEmpty) return null;
    return (sections.first as Map?)?['listById'] as Map<String, dynamic>?;
  }

  /// How a video can be played. Never cached: the delivery URL and the rights change with the moment.
  /// TF1+ answers 200 for refusals, so the body decides; only an unknown id gives a 404. A [bearerToken]
  /// makes the request come from that signed-in user instead of an anonymous visitor.
  Future<Map<String, dynamic>> mediaInfo(String videoId, {String? bearerToken}) {
    final uri = Uri.parse('$_mediaInfo/$videoId').replace(queryParameters: _mediaInfoQuery);
    return _fetch(uri, authorization: bearerToken == null ? null : 'Bearer $bearerToken');
  }

  Future<Map<String, dynamic>> _graphql(
    String id,
    Map<String, Object?> variables, {
    String gateway = _webGateway,
  }) async {
    final uri = Uri.parse(gateway).replace(queryParameters: {'id': id, 'variables': jsonEncode(variables)});
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < pacing.cacheTtl) return hit.body;

    final body = await _fetch(uri);
    final errors = body['errors'];
    if (body['data'] == null && errors is List && errors.isNotEmpty) {
      throw Tf1GraphqlException([for (final e in errors.whereType<Map>()) '${e['message']}']);
    }
    _forget(expiredBefore: DateTime.now().subtract(pacing.cacheTtl));
    _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  Map<String, dynamic>? _entity(Map<String, dynamic> body, String name) =>
      (body['data'] as Map?)?[name] as Map<String, dynamic>?;

  void _forget({required DateTime expiredBefore}) {
    if (_cache.length < 200) return;
    _cache.removeWhere((_, entry) => entry.at.isBefore(expiredBefore));
  }

  Future<Map<String, dynamic>> _fetch(Uri uri, {String? authorization}) async {
    final response = await _get(uri, authorization: authorization);
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

  /// Sends the request, waiting for its slot first and once more after a 429 when the wait is short.
  Future<MediaServerResponse> _get(Uri uri, {String? authorization}) async {
    final headers = {..._headers, 'Authorization': ?authorization};
    for (var attempt = 0; ; attempt++) {
      await _waitForSlot();
      final response = await _http.get(uri.toString(), headers: headers);
      if (response.statusCode != 429) return response;
      final wait = Duration(seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 30);
      if (attempt > 0 || wait > pacing.maxRetryWait) throw Tf1RateLimitedException(wait);
      await _delay(wait);
    }
  }

  /// Reserves the next request slot at once so concurrent callers queue behind each other.
  Future<void> _waitForSlot() async {
    final now = DateTime.now();
    final start = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = start.add(pacing.minInterval);
    final pause = start.difference(now);
    if (pause > Duration.zero) await _delay(pause);
  }
}
