import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'dw_mapper.dart';

/// Reads a video document of the content graph. DW streams are clear HLS with no account, no DRM and no per-title
/// country rule, so a video either has a stream, is still to be published, or is gone.
ReplayPlayback dwParsePlayback(Map<String, dynamic>? document, DateTime now) {
  final content = dwMap(dwMap(document?['data'])?['content']);
  if (content == null || content['__typename'] != 'Video') {
    return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  }
  final master = _masterUrl(content['hlsVideoSrc']);
  if (master == null) return _withoutStream(content, now);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: master, label: 'English')],
    subtitles: _subtitles(content['subtitles']),
  );
}

ReplayPlayback _withoutStream(Map<String, dynamic> content, DateTime now) {
  final published = dwDate(content['firstPublicationDate']);
  if (published != null && published.isAfter(now)) {
    return const ReplayPlayback.unavailable(ReplayAvailability.upcoming);
  }
  return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'DW has no video stream for this item');
}

Uri? _masterUrl(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty ? uri : null;
}

List<ReplaySubtitle> _subtitles(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value.whereType<Map<String, dynamic>>())
      if (_masterUrl(entry['subtitleUrl']) case final url?)
        ReplaySubtitle(url: url, languageCode: dwLine(entry['srcLanguage']) ?? 'en', label: _languageLabel(entry)),
  ];
}

String _languageLabel(Map<String, dynamic> entry) {
  final name = dwLine(entry['language']);
  if (name == null) return 'English';
  return name[0].toUpperCase() + name.substring(1).toLowerCase();
}
