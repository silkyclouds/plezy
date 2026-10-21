import 'dart:async';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import 'm6plus_auth_config.dart';

/// The broadcaster refused a request because too many were made in a short time.
class M6plusRateLimitedException implements Exception {
  final Duration retryAfter;

  const M6plusRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Trop de requêtes, réessayez dans ${retryAfter.inSeconds} s';
}

/// What a manifest host answered. The status is the whole point: a 403 names the blocked country.
class M6plusManifestProbe {
  final int statusCode;
  final String body;

  const M6plusManifestProbe(this.statusCode, this.body);
}

/// Thin JSON access to the open catalogue API behind M6+.
///
/// Requests are spaced by [minInterval] so a full catalogue sync stays well under the
/// three requests per second the broadcaster tolerates.
class M6plusApi {
  static const _base = 'https://pc.middleware.6play.fr/6play/v2/platforms/m6group_web/services/6play';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _ttl = Duration(minutes: 5);

  /// The server silently caps every list at this many items.
  static const pageSize = 100;

  final MediaServerHttpClient _http;
  final Duration minInterval;
  final Map<String, ({DateTime at, Object body})> _cache = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String?> Function()? _bearer;

  M6plusApi(this._http, {this.minInterval = const Duration(milliseconds: 250)});

  /// The client every call goes through, shared with the sign-in flow.
  MediaServerHttpClient get http => _http;

  /// Makes video calls carry the signed-in user's token, or anonymous again when [bearer] is null.
  ///
  /// Only video lists and single videos depend on the account (they hold the stream lists), so only
  /// their cached pages are dropped; programmes and folders stay cached across a sign-in or sign-out.
  void useBearer(Future<String?> Function()? bearer) {
    _bearer = bearer;
    _cache.removeWhere((key, _) => key.contains('/videos'));
  }

  /// One page of the whole catalogue, in the server's order.
  Future<List<Map<String, dynamic>>> programs(int offset) =>
      _list('programs', {'limit': '$pageSize', 'offset': '$offset', 'csa': '6', 'with': 'rights'});

  /// One page of a category ("folder").
  Future<List<Map<String, dynamic>>> folderPrograms(String folderId, int offset) => _list(
    'folders/$folderId/programs',
    {'limit': '$pageSize', 'offset': '$offset', 'csa': '6', 'with': 'rights,parentcontext'},
  );

  /// A programme with its counts and artwork, or null when it was withdrawn.
  Future<Map<String, dynamic>?> program(String id) => _object('programs/$id', {'with': 'links,subcats,rights'});

  /// One page of a programme's videos. [type] is `vi` (full), `vc` (extracts) or `podcast`.
  Future<List<Map<String, dynamic>>> videos(String programId, {required String type, int offset = 0, String? sort}) =>
      _list('programs/$programId/videos', {
        'csa': '6',
        'with': 'clips',
        'type': type,
        'limit': '$pageSize',
        'offset': '$offset',
        'sort': ?sort,
      }, signedIn: true);

  /// A single video with its stream list, or null when it is gone. Never cached: stream URLs are signed.
  Future<Map<String, dynamic>?> video(String clipId) =>
      _object('videos/$clipId', {'csa': '6', 'with': 'clips'}, cached: false, signedIn: true);

  /// Fetches a manifest only to learn whether the host lets this country in.
  Future<M6plusManifestProbe> probeManifest(Uri url) async {
    await _wait();
    final response = await _http.get(
      url.toString(),
      headers: const {'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'},
    );
    return M6plusManifestProbe(response.statusCode, response.data is String ? response.data as String : '');
  }

  Future<List<Map<String, dynamic>>> _list(String path, Map<String, String> query, {bool signedIn = false}) async {
    final body = await _json(path, query, cached: true, signedIn: signedIn);
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic>) item,
    ];
  }

  Future<Map<String, dynamic>?> _object(
    String path,
    Map<String, String> query, {
    bool cached = true,
    bool signedIn = false,
  }) async {
    try {
      final body = await _json(path, query, cached: cached, signedIn: signedIn);
      return body is Map<String, dynamic> ? body : null;
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Object> _json(String path, Map<String, String> query, {required bool cached, bool signedIn = false}) async {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: query);
    final key = uri.toString();
    final hit = _cache[key];
    if (cached && hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.body;

    await _wait();
    final response = await _http.get(key, headers: await _requestHeaders(signedIn));
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw M6plusRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
    final data = response.data;
    final body = data is String ? jsonDecode(data) : data;
    if (body is! Object) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Empty response',
      );
    }
    if (cached) _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  Future<Map<String, String>> _requestHeaders(bool signedIn) async {
    final token = signedIn ? await _bearer?.call() : null;
    if (token == null) return _headers;
    return {..._headers, 'Authorization': 'Bearer $token', 'X-Customer-Name': m6plusCustomer};
  }

  Future<void> _wait() async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(minInterval);
    final delay = slot.difference(now);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }
}
