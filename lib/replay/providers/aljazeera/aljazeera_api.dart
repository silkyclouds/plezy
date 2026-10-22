import 'dart:collection';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class AljazeeraRateLimitedException implements Exception {
  final Duration retryAfter;

  const AljazeeraRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The player key was refused twice, even after reading it again from the official player script.
class AljazeeraPolicyKeyRejectedException implements Exception {
  const AljazeeraPolicyKeyRejectedException();

  @override
  String toString() => 'Al Jazeera no longer accepts the player key this app uses';
}

/// A Brightcove answer that is not a playable video: the HTTP status and the first error code it carries.
class AljazeeraVideoReply {
  final int statusCode;
  final Object? body;

  const AljazeeraVideoReply(this.statusCode, this.body);
}

/// Thin access to the Al Jazeera English catalogue (GraphQL over GET) and to its Brightcove video account.
///
/// Requests are spaced out and lists are cached, because the site publishes hundreds of episodes per
/// programme and a season is found by probing single posts.
class AljazeeraApi {
  static const _host = 'www.aljazeera.com';
  static const _siteHeader = {'wp-site': 'aje'};
  static const _agent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
  static const _account = '665003303001';
  static const _playerScript = 'https://players.brightcove.net/$_account/6tKQRAx7lu_default/index.min.js';

  /// Public key that Brightcove's own player script ships to every visitor. It identifies the account's
  /// player, not a user. When it is rotated the script is read again, see [_readPolicyKey].
  static const defaultPolicyKey =
      'BCpkADawqM39agLpp-TuKJ3fi2ac40ghRBmnV3-bKKuO6oZSDAbOgt4HRS5TzFxLH2NA0XQdsoWQjrOYvmD2bVLQSYjxRgHufXokniy4kOamHBQs6UIbDSYvj2M';

  static const _listTtl = Duration(minutes: 5);
  static const _programmeTtl = Duration(days: 1);
  static const _cacheSize = 160;

  final MediaServerHttpClient _http;
  final Duration _minGap;
  final DateTime Function() _clock;
  final LinkedHashMap<String, ({DateTime at, Duration ttl, Map<String, dynamic> body})> _cache = LinkedHashMap();
  String _policyKey = defaultPolicyKey;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;

  AljazeeraApi(this._http, {this._minGap = const Duration(milliseconds: 250), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Programmes of a section (`tv-shows` or `documentary`), [quantity] at a time.
  Future<List<Map<String, dynamic>>> programmes(String category, {int offset = 0, int quantity = 60}) async {
    final body = await _graphql('ArchipelagoProgramsQuery', {
      'category': category,
      'quantity': quantity,
      'offset': offset,
    }, _programmeTtl);
    return _list(body, 'programs');
  }

  /// Episodes of a programme, newest first. Past the end the site answers with an error, which is an empty list.
  Future<List<Map<String, dynamic>>> posts(String category, {int offset = 0, int quantity = 20}) async {
    final body = await _graphql('ArchipelagoSectionPostsQuery', {
      'category': category,
      'categoryType': 'programs',
      'quantity': quantity,
      'offset': offset,
      'postTypes': ['episode'],
    }, _listTtl);
    return _list(body, 'articles');
  }

  /// The playback description of a video. Never cached: the stream addresses carry a signed token.
  ///
  /// A missing, removed or restricted video comes back as a reply with its error status instead of an exception.
  Future<AljazeeraVideoReply> video(String videoId) async {
    var reply = await _fetchVideo(videoId);
    if (reply.statusCode == 401) {
      final fresh = await _readPolicyKey();
      if (fresh != null && fresh != _policyKey) {
        _policyKey = fresh;
        reply = await _fetchVideo(videoId);
      }
    }
    if (reply.statusCode == 401) throw const AljazeeraPolicyKeyRejectedException();
    return reply;
  }

  void clearCache() => _cache.clear();

  Future<AljazeeraVideoReply> _fetchVideo(String videoId) async {
    final uri = Uri.https('edge.api.brightcove.com', '/playback/v1/accounts/$_account/videos/$videoId');
    final response = await _send(uri, {'Accept': 'application/json;pk=$_policyKey', 'User-Agent': _agent});
    if (response.statusCode >= 500) throwIfHttpError(response);
    return AljazeeraVideoReply(response.statusCode, response.data);
  }

  Future<String?> _readPolicyKey() async {
    final response = await _send(Uri.parse(_playerScript), {'User-Agent': _agent});
    final script = response.data;
    if (response.statusCode != 200 || script is! String) return null;
    return RegExp(r'policyKey:"(BCpk[A-Za-z0-9_-]+)"').firstMatch(script)?.group(1);
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> body, String field) {
    final data = body['data'];
    final list = data is Map ? data[field] : null;
    if (list is List) return list.whereType<Map<String, dynamic>>().toList();
    if (_onlyNoPostsError(body)) return const [];
    throw MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      message: 'Unexpected response shape: ${jsonEncode(body['errors'])}',
    );
  }

  bool _onlyNoPostsError(Map<String, dynamic> body) {
    final errors = body['errors'];
    return errors is List && errors.isNotEmpty && errors.every((e) => e is Map && e['message'] == 'no_posts_found');
  }

  Future<Map<String, dynamic>> _graphql(String operation, Map<String, Object?> variables, Duration ttl) async {
    final uri = Uri.https(_host, '/graphql', {
      'wp-site': 'aje',
      'operationName': operation,
      'variables': jsonEncode(variables),
    });
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && _clock().difference(hit.at) < hit.ttl) return hit.body;

    final response = await _send(uri, {'Accept': 'application/json', 'User-Agent': _agent, ..._siteHeader});
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
    _remember(key, data, ttl);
    return data;
  }

  void _remember(String key, Map<String, dynamic> body, Duration ttl) {
    _cache.remove(key);
    _cache[key] = (at: _clock(), ttl: ttl, body: body);
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<MediaServerResponse> _send(Uri uri, Map<String, String> headers) async {
    final blocked = _blockedUntil;
    if (blocked != null && blocked.isAfter(_clock())) throw AljazeeraRateLimitedException(blocked.difference(_clock()));
    await _waitForSlot();
    final response = await _http.get(uri.toString(), headers: headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      _blockedUntil = _clock().add(Duration(seconds: seconds));
      throw AljazeeraRateLimitedException(Duration(seconds: seconds));
    }
    return response;
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
