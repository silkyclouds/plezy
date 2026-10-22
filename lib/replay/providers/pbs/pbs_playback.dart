import 'dart:convert';

import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'pbs_api.dart';

const _geoMessage =
    'PBS only licenses most of its video for viewers in the United States, and for some shows Canada. '
    'This video is not available from your location.';
const _passportMessage = 'This video is for PBS Passport members. Plezy cannot sign in to PBS.';
const _marker = 'window.videoBridge = ';

/// Turns a video's player page into streams, or says why there are none.
///
/// PBS serves most full episodes only to the United States, and its search results do not tell which. The player
/// page and the stream redirector are the two places that refuse, so playback asks both.
class PbsPlayback {
  final PbsApi _api;
  final DateTime Function() _now;

  PbsPlayback(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<ReplayPlayback> resolve(String mediaId) async {
    final html = await _api.playerPage(mediaId);
    if (html == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    final bridge = pbsParseVideoBridge(html);
    if (bridge == null) return _withoutPlayer(html);
    return pbsRefusal(bridge, _now()) ?? await _streams(bridge);
  }

  ReplayPlayback _withoutPlayer(String html) => html.contains('Passport')
      ? const ReplayPlayback.unavailable(ReplayAvailability.loginRequired, message: _passportMessage)
      : const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage);

  Future<ReplayPlayback> _streams(Map<String, dynamic> bridge) async {
    final wantsHls = bridge['has_hls_encodings'] != false;
    Uri? mp4;
    for (final encoding in _encodings(bridge)) {
      final redirect = await _api.redirect(encoding);
      if (redirect.refusedRegion) {
        return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage);
      }
      final url = redirect.url;
      if (url == null) continue;
      if (url.path.endsWith('.m3u8')) {
        return ReplayPlayback(
          availability: ReplayAvailability.playable,
          streams: [ReplayStream(url: url, label: 'English')],
        );
      }
      mp4 ??= url;
      if (!wantsHls) break;
    }
    if (mp4 == null) {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.unknown,
        message: 'PBS returned no stream for this video.',
      );
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [ReplayStream(url: mp4, label: 'English (MP4)')],
      subtitles: _subtitles(bridge),
    );
  }

  /// The redirector addresses of the player page. Anything not on PBS's own redirector is ignored.
  List<Uri> _encodings(Map<String, dynamic> bridge) {
    final raw = bridge['encodings'];
    if (raw is! List) return const [];
    final found = <Uri>[];
    for (final entry in raw) {
      final uri = entry is String ? Uri.tryParse(entry) : null;
      if (uri != null && uri.scheme == 'https' && uri.host == 'urs.pbs.org') found.add(uri);
    }
    return found;
  }

  /// Caption files for a plain MP4. HLS masters carry their captions themselves.
  List<ReplaySubtitle> _subtitles(Map<String, dynamic> bridge) {
    final raw = bridge['cc_multiple_languages'];
    if (raw is! List) return const [];
    final byLanguage = <String, Map<String, dynamic>>{};
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final language = entry['language'];
      final profile = entry['profile'];
      if (language is! String || entry['url'] is! String || (profile != 'WebVTT' && profile != 'SRT')) continue;
      final kept = byLanguage[language];
      if (kept == null || (kept['profile'] == 'SRT' && profile == 'WebVTT')) byLanguage[language] = entry;
    }
    return [
      for (final MapEntry(key: language, value: entry) in byLanguage.entries)
        if (Uri.tryParse(entry['url'] as String) case final url?)
          ReplaySubtitle(url: url, languageCode: language, label: _languageName(language)),
    ];
  }
}

/// Why a player page's own data says the video cannot be played, or null when it says nothing against it.
ReplayPlayback? pbsRefusal(Map<String, dynamic> bridge, DateTime now) {
  if (bridge['has_drm'] == true) {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.drmProtected,
      message: 'This video is copy-protected and cannot be played here.',
    );
  }
  final playable = bridge['is_playable'] != false && bridge['availability'] != 'unavailable';
  if (bridge['is_mvod'] == true && bridge['is_playable'] != true) {
    return const ReplayPlayback.unavailable(ReplayAvailability.loginRequired, message: _passportMessage);
  }
  final until = DateTime.tryParse('${bridge['expire_date']}');
  if (until != null && until.isBefore(now)) {
    return const ReplayPlayback.unavailable(ReplayAvailability.expired, message: 'PBS has taken this video offline.');
  }
  if (!playable) return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage);
  return null;
}

/// The playback description PBS embeds in a player page as `window.videoBridge = {...};`, or null when the page
/// holds none, which is what a video refused for the viewer's country looks like.
Map<String, dynamic>? pbsParseVideoBridge(String html) {
  final at = html.indexOf(_marker);
  if (at < 0) return null;
  final start = at + _marker.length;
  final end = _objectEnd(html, start);
  if (end == null) return null;
  try {
    final decoded = jsonDecode(html.substring(start, end));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Index just past the JSON object that starts at [start], or null when it never closes.
int? _objectEnd(String text, int start) {
  if (start >= text.length || text[start] != '{') return null;
  var depth = 0;
  var inString = false;
  for (var i = start; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (c == 0x5C) {
        i++;
      } else if (c == 0x22) {
        inString = false;
      }
    } else if (c == 0x22) {
      inString = true;
    } else if (c == 0x7B) {
      depth++;
    } else if (c == 0x7D && --depth == 0) {
      return i + 1;
    }
  }
  return null;
}

String _languageName(String code) => switch (code) {
  'en' => 'English',
  'es' => 'Spanish',
  'fr' => 'French',
  _ => code.toUpperCase(),
};
