import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:http/http.dart' as http;

import '../../auth/replay_auth.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'rtlplay_cookie_jar.dart';
import 'rtlplay_jwt.dart';
import 'rtlplay_play_config.dart';
import 'rtlplay_session.dart';
import 'rtlplay_web_client.dart';

/// Public application key the website ships to every visitor for its browser player.
const _playerApiKey = '2W7kCXUTyUgKf7HKlK9qcYJvFmiPFaBEFT90eC2b';
const _playerSdkVersion = '8';
const _tokenMargin = Duration(seconds: 30);

final _playConfig = Uri.parse('https://videoplayer-service.dpgmedia.net/play-config');
final _nextData = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true);

/// The player page cannot hand out a token; [playback] says why.
class _PageRefused implements Exception {
  final ReplayPlayback playback;

  const _PageRefused(this.playback);
}

/// Resolves a playable id to streams for the signed-in viewer, the way the website's player does:
/// the player page, rendered for the viewer's cookies, carries the bearer token that the stream
/// service then asks for.
class RtlPlayStreamService {
  final http.Client _client;
  final DateTime Function() _now;
  final Future<ReplaySession> Function(ReplaySession expired) _renew;
  ReplaySession? _session;
  ({String token, String contentId, DateTime expiry})? _bearer;

  /// Told about every session this service renews by itself, so the app can store it.
  void Function(ReplaySession session)? onSessionRenewed;

  RtlPlayStreamService(this._client, this._renew, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  bool get isSignedIn => _session != null;

  /// Switches the viewer; the previous viewer's bearer token is dropped with them.
  void useSession(ReplaySession? session) {
    _session = session;
    _bearer = null;
  }

  Future<ReplayPlayback> resolve(String playableId) async {
    final session = _session;
    if (session == null) return _signInAgain();
    try {
      final bearer = await _bearerFor(await _current(session), playableId);
      final playback = await _askPlayer(bearer.token, bearer.contentId);
      if (playback.availability == ReplayAvailability.loginRequired) _bearer = null;
      return playback;
    } on _PageRefused catch (e) {
      return e.playback;
    } on http.ClientException {
      return _unreachable();
    } on TimeoutException {
      return _unreachable();
    }
  }

  Future<({String token, String contentId, DateTime expiry})> _bearerFor(ReplaySession session, String id) async {
    final cached = _bearer;
    if (cached != null && cached.contentId == id && cached.expiry.isAfter(_now().add(_tokenMargin))) return cached;
    final jar = rtlPlayJarFromSession(session);
    final page = await RtlPlayWebClient(_client, jar).get(Uri.https(rtlPlayWebHost, '/rtlplay/player/$id'));
    _adoptRotatedCookies(session, jar);
    if (page.status == 429 || page.status >= 500) throw _PageRefused(rtlPlayPlaybackFromConfig(page.status, null));
    final props = page.status == 200 ? _pageProps(page.body) : null;
    final token = props?['authToken'];
    if (token is! String || token.isEmpty) throw _PageRefused(_signInAgain());
    final contentId = props?['id'] is String ? props!['id'] as String : id;
    final expiry = rtlPlayJwtExpiry(token);
    final bearer = (token: token, contentId: contentId, expiry: expiry ?? _now());
    if (expiry != null) _bearer = bearer;
    return bearer;
  }

  /// The session to use now: an expired one is renewed first, and the new one is reported.
  Future<ReplaySession> _current(ReplaySession session) async {
    if (!session.isExpiredAt(_now())) return session;
    try {
      final renewed = await _renew(session);
      _adopt(renewed);
      return renewed;
    } on ReplayAuthException {
      throw _PageRefused(_signInAgain());
    }
  }

  /// The site may rotate its cookies on any page: keep the newest, and report it when it changed.
  void _adoptRotatedCookies(ReplaySession session, RtlPlayCookieJar jar) {
    final latest = rtlPlaySessionFromJar(jar, accountLabel: session.accountLabel);
    if (latest == null || mapEquals(latest.values, session.values)) return;
    _adopt(latest);
  }

  void _adopt(ReplaySession session) {
    _session = session;
    onSessionRenewed?.call(session);
  }

  Map<String, dynamic>? _pageProps(String html) {
    final json = _nextData.firstMatch(html)?.group(1);
    if (json == null) return null;
    try {
      final data = jsonDecode(json);
      final props = data is Map<String, dynamic> ? data['props'] : null;
      final pageProps = props is Map<String, dynamic> ? props['pageProps'] : null;
      return pageProps is Map<String, dynamic> ? pageProps : null;
    } on FormatException {
      return null;
    }
  }

  Future<ReplayPlayback> _askPlayer(String token, String contentId) async {
    final uri = _playConfig.replace(
      pathSegments: [..._playConfig.pathSegments, contentId],
      queryParameters: {'startPosition': '0.0', 'autoPlay': 'true'},
    );
    final response = await RtlPlayWebClient(_client, RtlPlayCookieJar()).postJson(
      uri,
      {'deviceType': 'web', 'zone': 'rtlplay'},
      headers: {
        'accept': 'application/json',
        'x-api-key': _playerApiKey,
        'popcorn-sdk-version': _playerSdkVersion,
        'authorization': 'Bearer $token',
      },
    );
    return rtlPlayPlaybackFromConfig(response.status, _json(response.body));
  }

  Object? _json(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  ReplayPlayback _signInAgain() => const ReplayPlayback.unavailable(
    ReplayAvailability.loginRequired,
    message: 'Sign in to your RTL account to play this',
  );

  ReplayPlayback _unreachable() => const ReplayPlayback.unavailable(
    ReplayAvailability.unknown,
    message: 'Could not reach RTL Play, try again later',
  );
}
