import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'zdfmediathek_dates.dart';
import 'zdfmediathek_text.dart';

const _hlsType = 'h264_aac_ts_http_m3u8_http';
const _mp4Type = 'h264_aac_mp4_http_na_na';
const _hlsQualities = ['auto', 'veryhigh', 'high', 'med', 'low'];
const _mp4Qualities = ['fhd', 'hd', 'veryhigh', 'high', 'low'];

/// Reads a video document into a playback answer.
///
/// ZDF answers 200 with full metadata for videos that cannot be watched. What decides is the end of the
/// availability window, the start of it, and the stream list, which is empty behind an age check. The country
/// restriction shows only when the stream is fetched, so it is the caller's to probe (see [zdfGeoFlag]).
ReplayPlayback zdfParsePlayback(Map<String, dynamic> page, {required DateTime now}) {
  final document = page['document'];
  if (document is! Map<String, dynamic> || document['type'] != 'video') {
    return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  }
  final info = zdfText(document['availabilityInfo']);
  final end = zdfIsoDate(document['offlineAvailability']) ?? zdfLocalDate(document['timetolive']);
  if (end != null && end.isBefore(now)) return ReplayPlayback.unavailable(ReplayAvailability.expired, message: info);

  final streams = _streams(document['formitaeten']);
  if (streams.isEmpty) {
    final start = zdfLocalDate(document['visibleFrom']);
    if (start != null && start.isAfter(now)) {
      return ReplayPlayback.unavailable(ReplayAvailability.upcoming, message: info);
    }
    final reason = document['fskCheck'] == true ? ReplayAvailability.timeSlotRestricted : ReplayAvailability.unknown;
    return ReplayPlayback.unavailable(reason, message: info);
  }
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: streams,
    subtitles: _subtitles(document['captions']),
  );
}

/// The country flag of a video document: `none`, `dach`, `de`.
String? zdfGeoFlag(Map<String, dynamic> page) => (page['document'] as Map?)?['geoLocation'] as String?;

/// The viewer-facing note of a document, such as "Video verfügbar bis 03.03.2031, in Deutschland".
String? zdfAvailabilityNote(Map<String, dynamic> page) => zdfText((page['document'] as Map?)?['availabilityInfo']);

List<ReplayStream> _streams(Object? formitaeten) {
  if (formitaeten is! List) return const [];
  final entries = [
    for (final raw in formitaeten.whereType<Map<String, dynamic>>())
      if (Uri.tryParse(raw['url'] as String? ?? '')?.hasScheme ?? false) raw,
  ];
  final main = _ofClass(entries, 'main');
  final described = _byQuality(_ofClass(entries, 'ad'), _hlsType, const ['auto']);
  return [
    if (_bestMain(main) case final entry?) ReplayStream(url: Uri.parse(entry['url'] as String), label: 'Deutsch'),
    if (described != null) ReplayStream(url: Uri.parse(described['url'] as String), label: 'Audiodeskription'),
  ];
}

List<Map<String, dynamic>> _ofClass(List<Map<String, dynamic>> entries, String audioClass) => [
  for (final entry in entries)
    if ((entry['class'] ?? 'main') == audioClass) entry,
];

/// The playlist to play: the HLS master when there is one, else the best HLS rendition, else the best progressive
/// MP4. The list is long and unordered, so each candidate is looked up by type and quality.
Map<String, dynamic>? _bestMain(List<Map<String, dynamic>> entries) =>
    _byQuality(entries, _hlsType, _hlsQualities) ?? _byQuality(entries, _mp4Type, _mp4Qualities);

Map<String, dynamic>? _byQuality(List<Map<String, dynamic>> entries, String type, List<String> order) {
  for (final quality in order) {
    for (final entry in entries) {
      if (entry['type'] == type && entry['quality'] == quality) return entry;
    }
  }
  return null;
}

List<ReplaySubtitle> _subtitles(Object? captions) {
  if (captions is! List) return const [];
  return [
    for (final raw in captions.whereType<Map<String, dynamic>>())
      if (raw['format'] == 'webvtt' && Uri.tryParse(raw['uri'] as String? ?? '')?.hasScheme == true)
        ReplaySubtitle(
          url: Uri.parse(raw['uri'] as String),
          languageCode: _language(raw['language']),
          label: raw['class'] == 'hoh' ? '${_languageName(raw['language'])} (SDH)' : _languageName(raw['language']),
        ),
  ];
}

String _language(Object? code) => switch (code) {
  'deu' || 'ger' || null => 'de',
  'eng' => 'en',
  final String other => other,
  _ => 'de',
};

String _languageName(Object? code) => switch (_language(code)) {
  'de' => 'Deutsch',
  'en' => 'English',
  final other => other,
};
