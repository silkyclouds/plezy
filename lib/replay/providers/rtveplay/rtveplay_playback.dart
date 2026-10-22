import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'rtveplay_api.dart';

final _encryptedPlaylist = RegExp(r'#EXT-X-(?:SESSION-)?KEY:[^\n]*METHOD=(?!NONE)', caseSensitive: false);

/// The manifest to play out of the addresses RTVE resolved: HLS first, then DASH. The progressive MP4 is left out:
/// it is served over plain HTTP and cannot be checked without downloading it.
Uri? rtvePickManifest(List<Uri> urls) {
  for (final extension in ['.m3u8', '.mpd']) {
    for (final url in urls) {
      if (url.path.endsWith(extension)) return url;
    }
  }
  return null;
}

/// What a manifest request says about playing the video. RTVE answers 200 for a playable video and an empty 403 for
/// one the viewer may not watch; the answer does not tell a country limit from a licensing one, so both are reported
/// as [ReplayAvailability.geoBlocked].
ReplayPlayback? rtveRefusal(RtveProbe probe) {
  final status = probe.status;
  if (status >= 200 && status < 300) {
    final protected = _encryptedPlaylist.hasMatch(probe.body) || probe.body.contains('<ContentProtection');
    return protected
        ? const ReplayPlayback.unavailable(
            ReplayAvailability.drmProtected,
            message: 'This video is encrypted and cannot be played here.',
          )
        : null;
  }
  if (status == 403) {
    final country = probe.headers['x-country'];
    return ReplayPlayback.unavailable(
      ReplayAvailability.geoBlocked,
      message: country == null
          ? 'RTVE refused this video: it is limited to Spain or needs an RTVE account.'
          : 'RTVE does not offer this video in your country (${country.toUpperCase()}).',
    );
  }
  if (status == 404 || status == 410) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'RTVE answered HTTP $status.');
}

const _languageNames = {
  'es': 'Español',
  'en': 'English',
  'gl': 'Galego',
  'ca': 'Català',
  'eu': 'Euskara',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
};

/// Every subtitle track of a video, as external WebVTT files. RTVE offers a track per language, some of them
/// machine translations.
List<ReplaySubtitle> rtveParseSubtitles(Map<String, dynamic> page) {
  final items = (page['page'] as Map?)?['items'];
  if (items is! List) return const [];
  final seen = <String>{};
  final tracks = <ReplaySubtitle>[];
  for (final item in items.whereType<Map<String, dynamic>>()) {
    final src = item['src'];
    final lang = item['lang'];
    final url = src is String ? Uri.tryParse(src) : null;
    if (url == null || !url.hasScheme || lang is! String || lang.isEmpty || !seen.add(url.toString())) continue;
    tracks.add(
      ReplaySubtitle(url: url, languageCode: lang, label: _languageNames[lang.toLowerCase()] ?? lang.toUpperCase()),
    );
  }
  return tracks;
}
