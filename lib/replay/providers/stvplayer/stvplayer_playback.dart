import 'dart:convert';

import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'stvplayer_access.dart';
import 'stvplayer_api.dart';
import 'stvplayer_refs.dart';

// STV's web player ships these two values to every visitor; they only identify its video account to Brightcove.
const _brightcoveAccount = '1486976045';
const _brightcovePolicyKey =
    'BCpkADawqM1WJ12PwtUWqGXx3nbAo2XVSxyAQxPRZKBc75svhrUB9qIMPN_d9US0Vib5smumeNMbntSmZIpzeVV1iUrnzYgf5k7UMaVN46PGYe_oSZ-xbPVnsm4';
const _brightcoveBase = 'https://edge.api.brightcove.com/playback/v1/accounts/$_brightcoveAccount/videos';

const _messages = {
  ReplayAvailability.geoBlocked: 'STV Player can only be watched from the United Kingdom.',
  ReplayAvailability.drmProtected: 'This programme is copy-protected and cannot be played here.',
  ReplayAvailability.loginRequired: 'This programme needs an STV account.',
  ReplayAvailability.expired: 'This programme is no longer available.',
  ReplayAvailability.upcoming: 'This programme is not available yet.',
};

/// Resolves an episode or clip to a clear stream through Brightcove's playback API.
///
/// The catalogue names the Brightcove video; Brightcove answers with the sources, or with 403 `CLIENT_GEO` outside the
/// UK. That answer is reported as geo-blocked and never retried another way. Sources that list `key_systems` are
/// copy-protected and are never offered.
class StvPlayerPlayback {
  final MediaServerHttpClient _http;
  final StvPlayerApi _api;
  final DateTime Function() _now;

  StvPlayerPlayback(this._http, this._api, this._now);

  Future<ReplayPlayback> resolve(ReplayRef ref) async {
    final target = StvTarget.parse(ref.nativeId);
    final id = target.id;
    if (id == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

    final item = target.kind == StvTargetKind.clip
        ? await _api.clip(id, fresh: true)
        : await _api.episode(id, fresh: true);
    if (item == null) return _unavailable(ReplayAvailability.expired);

    final blocked = stvPlayerAvailability(item, _now());
    if (blocked != ReplayAvailability.playable) return _unavailable(blocked);

    final videoId = (item['video'] as Map?)?['id'] ?? (item['standardVideo'] as Map?)?['id'];
    if (videoId == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

    final response = await _http.get(
      '$_brightcoveBase/$videoId',
      headers: {...stvPlayerHeaders, 'Accept': 'application/json;pk=$_brightcovePolicyKey'},
    );
    return _fromResponse(response, item);
  }

  ReplayPlayback _fromResponse(MediaServerResponse response, Map<String, dynamic> item) {
    final body = _decoded(response.data);
    switch (response.statusCode) {
      case 404:
        return _unavailable(ReplayAvailability.expired);
      case 401 || 403 || 429:
        return _refusal(response.statusCode, body);
    }
    throwIfHttpError(response);
    if (body is! Map<String, dynamic>) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    return _fromSources(body, item);
  }

  ReplayPlayback _fromSources(Map<String, dynamic> body, Map<String, dynamic> item) {
    final sources = [
      for (final s in (body['sources'] as List? ?? const []))
        if (s is Map<String, dynamic>) s,
    ];
    final clear = [
      for (final s in sources)
        if (!_isProtected(s) && (s['src'] as String? ?? '').startsWith('https://')) s,
    ];
    final chosen = _preferred(clear);
    if (chosen == null) {
      final reason = sources.any(_isProtected) ? ReplayAvailability.drmProtected : ReplayAvailability.unknown;
      return _unavailable(reason, fallback: 'STV Player offered no clear stream for this title.');
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [ReplayStream(url: Uri.parse(chosen['src'] as String), label: 'STV')],
      subtitles: _subtitles(item, body),
    );
  }

  ReplayPlayback _refusal(int status, Object? body) {
    final errors = _errors(body);
    if (status == 403 && errors.any((e) => '${e['error_subcode']}'.contains('GEO'))) {
      return _unavailable(ReplayAvailability.geoBlocked);
    }
    final message = errors.map((e) => e['message']).whereType<String>().firstOrNull;
    return ReplayPlayback.unavailable(
      ReplayAvailability.unknown,
      message: message ?? 'STV Player refused the request (HTTP $status).',
    );
  }
}

ReplayPlayback _unavailable(ReplayAvailability reason, {String? fallback}) =>
    ReplayPlayback.unavailable(reason, message: _messages[reason] ?? fallback);

bool _isProtected(Map<String, dynamic> source) {
  final systems = source['key_systems'];
  return systems is Map && systems.isNotEmpty;
}

/// HLS first, then DASH, then a plain file. One stream is enough: the others are the same programme.
Map<String, dynamic>? _preferred(List<Map<String, dynamic>> sources) {
  for (final matches in [_isHls, _isDash, _isMp4]) {
    final hit = sources.where(matches).firstOrNull;
    if (hit != null) return hit;
  }
  return null;
}

bool _isHls(Map<String, dynamic> s) =>
    '${s['type']}'.toLowerCase().contains('mpegurl') || '${s['src']}'.contains('.m3u8');

bool _isDash(Map<String, dynamic> s) => '${s['type']}'.toLowerCase().contains('dash+xml');

bool _isMp4(Map<String, dynamic> s) => '${s['type']}'.toLowerCase() == 'video/mp4';

/// The catalogue's WebVTT file when it has one, else the caption tracks Brightcove lists.
List<ReplaySubtitle> _subtitles(Map<String, dynamic> item, Map<String, dynamic> body) {
  final webvtt = (item['_subtitles'] as Map?)?['webvtt'];
  if (webvtt is String && webvtt.startsWith('https://')) {
    return [ReplaySubtitle(url: Uri.parse(webvtt), languageCode: 'en', label: 'English')];
  }
  return [
    for (final t in (body['text_tracks'] as List? ?? const []))
      if (t is Map<String, dynamic> &&
          (t['kind'] == 'captions' || t['kind'] == 'subtitles') &&
          (t['src'] as String? ?? '').startsWith('https://'))
        ReplaySubtitle(
          url: Uri.parse(t['src'] as String),
          languageCode: (t['srclang'] as String?) ?? 'en',
          label: (t['label'] as String?) ?? 'English',
        ),
  ];
}

Object? _decoded(Object? data) {
  if (data is! String) return data;
  try {
    return jsonDecode(data);
  } on FormatException {
    return null;
  }
}

/// Brightcove reports errors as a list of objects, with `error_code`, `error_subcode` and `message`.
List<Map<String, dynamic>> _errors(Object? body) =>
    body is List ? body.whereType<Map<String, dynamic>>().toList() : const [];
