import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// RÚV answered 429; [retryAfter] is how long it asked callers to wait.
class RuvRateLimitedException implements Exception {
  final Duration retryAfter;

  const RuvRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The GraphQL endpoint returned errors and no data.
class RuvQueryException implements Exception {
  final String message;

  const RuvQueryException(this.message);

  @override
  String toString() => 'RÚV query failed: $message';
}

/// What the CDN said about a stream manifest: a status and, for a 200, the playlist text.
typedef RuvManifestProbe = ({int status, String body});

/// Thin access to RÚV's GraphQL catalogue and to its HLS manifests.
class RuvApi {
  static const _endpoint = 'https://www.ruv.is/gql/';
  static const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _headers = {'Accept': 'application/json', 'User-Agent': _userAgent};

  /// Programme lists change a few times a day; details and batches change when an episode is published.
  static const listTtl = Duration(minutes: 15);
  static const detailsTtl = Duration(minutes: 5);
  static const wholeCatalogueTtl = Duration(hours: 12);
  static const _maxCached = 80;

  final MediaServerHttpClient _http;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Map<String, dynamic> data})> _cache = {};

  RuvApi(this._http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Runs a catalogue query and returns its `data` object, cached for [ttl].
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, Object?> variables = const {},
    Duration ttl = listTtl,
  }) async {
    final key = '$document|${jsonEncode(variables)}';
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.data;
    final data = await fetch(document, variables: variables);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = (at: _now(), data: data);
    return data;
  }

  /// A query that is never served from the cache: rights and expiry are read at the moment of play.
  Future<Map<String, dynamic>> fetch(String document, {Map<String, Object?> variables = const {}}) async {
    final response = await _http.post(
      _endpoint,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': document, 'variables': variables}),
    );
    _checkStatus(response);
    return _dataOf(response);
  }

  /// Fetches an HLS master playlist. 401 and 403 are answers, not failures: the CDN refuses viewers outside Iceland
  /// for Iceland-only titles.
  Future<RuvManifestProbe> probeManifest(Uri manifest) async {
    final response = await _http.get(manifest.toString(), headers: {'User-Agent': _userAgent});
    final status = response.statusCode;
    if (status == 401 || status == 403 || status == 404) return (status: status, body: '');
    _checkStatus(response);
    final body = response.data;
    return (status: status, body: body is String ? body : '');
  }

  void _checkStatus(MediaServerResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw RuvRateLimitedException(Duration(seconds: seconds));
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
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    final errors = body['errors'];
    final first = errors is List ? errors.firstOrNull : null;
    final message = first is Map ? first['message'] : null;
    throw RuvQueryException('${message ?? 'no data in the response'}');
  }
}
