import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_json.dart';
import 'ardmediathek_region.dart';

const _hlsMimeType = 'application/vnd.apple.mpegurl';
const _audioDescription = 'audio-description';

/// What a video page says about playing the video, before any stream is requested.
class ArdItemFacts {
  /// [ReplayAvailability.playable] when the page offers streams; otherwise the reason it does not.
  final ReplayAvailability availability;

  /// The gateway marks the video as licensed for Germany or the DACH region only.
  final bool geoFlagged;
  final ArdRegion region;
  final Uri? main;
  final Uri? audioDescription;
  final List<ReplaySubtitle> subtitles;

  const ArdItemFacts({
    required this.availability,
    this.geoFlagged = false,
    this.region = ArdRegion.worldwide,
    this.main,
    this.audioDescription,
    this.subtitles = const [],
  });

  const ArdItemFacts.unavailable(ReplayAvailability reason) : this(availability: reason);

  bool get isPlayable => availability == ReplayAvailability.playable && main != null;
}

/// Reads the first widget of a video page.
///
/// Gates are checked in the order a viewer would meet them: an account, then the evening age window, then the
/// end of the rights. A page without a media collection that is none of these is a video not published yet.
ArdItemFacts ardReadItem(Map<String, dynamic> page, {required DateTime now}) {
  final widget = ardMaps(page['widgets']).firstOrNull;
  if (widget == null) return const ArdItemFacts.unavailable(ReplayAvailability.unknown);

  if (widget['blockedByLoginOnly'] == true) return const ArdItemFacts.unavailable(ReplayAvailability.loginRequired);
  if (widget['blockedByFsk'] == true) return const ArdItemFacts.unavailable(ReplayAvailability.timeSlotRestricted);
  final end = ardDate(widget['availableTo']);
  if (end != null && end.isBefore(now)) return const ArdItemFacts.unavailable(ReplayAvailability.expired);

  final collection = ardMap(ardMap(widget['mediaCollection'])?['embedded']);
  final media = _mainMedia(collection);
  if (collection == null || media.isEmpty) {
    final broadcast = ardDate(widget['broadcastedOn']);
    return ArdItemFacts.unavailable(
      broadcast != null && broadcast.isAfter(now) ? ReplayAvailability.upcoming : ReplayAvailability.unknown,
    );
  }

  final main = _best(media, 'standard');
  final flagged = collection['isGeoBlocked'] == true;
  return ArdItemFacts(
    availability: main == null ? ReplayAvailability.unknown : ReplayAvailability.playable,
    geoFlagged: flagged,
    region: ardRegionOf(main, flagged: flagged),
    main: main,
    audioDescription: _best(media, _audioDescription),
    subtitles: _subtitles(ardMaps(collection['subtitles'])),
  );
}

List<Map<String, dynamic>> _mainMedia(Map<String, dynamic>? collection) {
  final streams = ardMaps(collection?['streams']);
  final main = streams.where((s) => s['kind'] == 'main').firstOrNull ?? streams.firstOrNull;
  return ardMaps(main?['media']);
}

/// The HLS master of one audio kind, else its tallest MP4. The URL is kept verbatim: some CDNs carry opaque query parts.
Uri? _best(List<Map<String, dynamic>> media, String audioKind) {
  final ofKind = [
    for (final m in media)
      if ((ardText(ardMaps(m['audios']).firstOrNull?['kind']) ?? 'standard') == audioKind) m,
  ];
  final hls = ofKind.where((m) => m['mimeType'] == _hlsMimeType).firstOrNull;
  if (hls != null) return _url(hls);
  final files = [
    for (final m in ofKind)
      if (m['mimeType'] == 'video/mp4') m,
  ]..sort((a, b) => (ardInt(b['maxVResolutionPx']) ?? 0).compareTo(ardInt(a['maxVResolutionPx']) ?? 0));
  return files.isEmpty ? null : _url(files.first);
}

Uri? _url(Map<String, dynamic> media) {
  final raw = ardText(media['url']);
  if (raw == null) return null;
  return Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
}

List<ReplaySubtitle> _subtitles(List<Map<String, dynamic>> entries) {
  final result = <ReplaySubtitle>[];
  for (final entry in entries) {
    final source = ardMaps(entry['sources']).where((s) => s['kind'] == 'webvtt').firstOrNull;
    final url = Uri.tryParse(ardText(source?['url']) ?? '');
    if (url == null || !url.hasScheme) continue;
    final code = _languageCode(ardText(entry['languageCode']) ?? 'deu');
    final hearingImpaired = entry['kind'] == 'closed-captions';
    result.add(
      ReplaySubtitle(url: url, languageCode: code, label: '${_languageName(code)}${hearingImpaired ? ' (SDH)' : ''}'),
    );
  }
  return result;
}

const _languages = {
  'deu': ('de', 'Deutsch'),
  'eng': ('en', 'English'),
  'fra': ('fr', 'Français'),
  'tur': ('tr', 'Türkçe'),
};

String _languageCode(String code) => _languages[code]?.$1 ?? code;

String _languageName(String code) {
  for (final entry in _languages.values) {
    if (entry.$1 == code) return entry.$2;
  }
  return code;
}
