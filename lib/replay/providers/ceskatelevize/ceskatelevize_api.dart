import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster asked for fewer requests; try again after [retryAfter].
class CeskaTelevizeRateLimitedException implements Exception {
  final Duration retryAfter;

  const CeskaTelevizeRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The catalogue has no page for the id that was asked for.
class CeskaTelevizeNotFoundException implements Exception {
  const CeskaTelevizeNotFoundException();

  @override
  String toString() => 'Not found';
}

/// A GraphQL answer with errors and no data.
class CeskaTelevizeQueryException implements Exception {
  final String message;

  const CeskaTelevizeQueryException(this.message);

  @override
  String toString() => 'Česká televize query failed: $message';
}

/// What the playlist endpoint answered: a status and the JSON body, for both success and refusals.
typedef CeskaTelevizePlaylistReply = ({int status, Object? body});

/// Access to the iVysílání catalogue (GraphQL) and its playlist endpoint.
class CeskaTelevizeApi {
  static const _graphqlUrl = 'https://api.ceskatelevize.cz/graphql/';
  static const _playlistUrl = 'https://api.ceskatelevize.cz/video/v1/playlist-vod/v1/stream-data/media/external';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  static const listTtl = Duration(minutes: 15);
  static const detailsTtl = Duration(minutes: 5);
  static const menuTtl = Duration(hours: 24);
  static const _maxCached = 200;
  static const _maxInFlight = 4;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> data})> _cache = {};
  final _InFlightLimit _gate = _InFlightLimit(_maxInFlight);

  CeskaTelevizeApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Runs a query and returns its `data` object, cached for [ttl].
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, Object?> variables = const {},
    Duration ttl = listTtl,
  }) async {
    final key = '$document|${jsonEncode(variables)}';
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.data;

    final response = await _gate.run(
      () => _http.post(
        _graphqlUrl,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'query': document, 'variables': variables}),
      ),
    );
    _checkStatus(response);
    final data = _dataOf(response);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), data: data);
    return data;
  }

  /// Playback information for an episode id. Never cached: rights and the stream token are read at the moment of play.
  ///
  /// Refusals (403, 404) come back as a reply so the caller can read the reason; other failures throw.
  Future<CeskaTelevizePlaylistReply> playlist(String idec) async {
    final url = '$_playlistUrl/$idec?canPlayDrm=false&streamType=hls&quality=web&origin=ivysilani';
    final response = await _gate.run(() => _http.get(url, headers: _headers));
    if (response.statusCode == 403 || response.statusCode == 404) {
      return (status: response.statusCode, body: response.data);
    }
    _checkStatus(response);
    return (status: response.statusCode, body: response.data);
  }

  void _checkStatus(MediaServerResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw CeskaTelevizeRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
  }

  Map<String, dynamic> _dataOf(MediaServerResponse response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: response.requestUri,
        message: 'Unexpected response shape',
      );
    }
    final errors = body['errors'];
    final first = errors is List && errors.isNotEmpty && errors.first is Map ? errors.first as Map : null;
    if ((first?['extensions'] as Map?)?['code'] == 'NOT_FOUND') throw const CeskaTelevizeNotFoundException();
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    throw CeskaTelevizeQueryException('${first?['message'] ?? 'no data in the response'}');
  }
}

/// Lets a fixed number of requests run at once and queues the rest, so a page of rails does not open a dozen sockets.
class _InFlightLimit {
  final int _limit;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  _InFlightLimit(this._limit);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= _limit) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _active++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}
