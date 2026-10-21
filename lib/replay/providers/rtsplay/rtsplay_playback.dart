import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'rtsplay_availability.dart';

/// Reads a media composition.
///
/// The server answers 200 for geoblocked, expired and protected videos, so the chapter's block reason
/// and its resource list decide. A protected stream is only visible here, never in a list.
ReplayPlayback rtsParsePlayback(Map<String, dynamic> composition, {DateTime? now}) {
  final chapters = composition['chapterList'];
  final chapter = chapters is List && chapters.isNotEmpty ? chapters.first : null;
  if (chapter is! Map<String, dynamic>) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

  final state = rtsAvailability(chapter, now ?? DateTime.now());
  if (state != ReplayAvailability.playable) return ReplayPlayback.unavailable(state);

  final resources = [
    for (final r in (chapter['resourceList'] as List? ?? const []))
      if (r is Map<String, dynamic> && r['url'] is String && r['live'] != true) r,
  ];
  if (resources.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.expired);

  final clear = resources.where((r) => !_isProtected(r)).toList();
  final stream = _pick(clear, 'HLS') ?? _pick(clear, 'PROGRESSIVE');
  if (stream == null) return _protected(resources);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: Uri.parse(stream['url'] as String), label: _label(stream))],
  );
}

Map<String, dynamic>? _pick(List<Map<String, dynamic>> resources, String streaming) =>
    resources.where((r) => r['streaming'] == streaming).firstOrNull;

/// Protected streams list their schemes in `drmList` and live on a separate CDN host.
bool _isProtected(Map<String, dynamic> resource) {
  final drm = resource['drmList'];
  if (drm is List && drm.isNotEmpty) return true;
  return (Uri.tryParse(resource['url'] as String)?.host ?? '').contains('-drm');
}

ReplayPlayback _protected(List<Map<String, dynamic>> resources) {
  final schemes = {
    for (final r in resources)
      for (final d in (r['drmList'] as List? ?? const []))
        if (d is Map && d['type'] is String) d['type'] as String,
  };
  if (schemes.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  return ReplayPlayback.unavailable(ReplayAvailability.drmProtected, message: 'DRM: ${schemes.join(', ')}');
}

/// "VF" for the French soundtrack, otherwise the language code of the first audio track.
String _label(Map<String, dynamic> resource) {
  final tracks = resource['audioTrackList'];
  final first = tracks is List ? tracks.whereType<Map<String, dynamic>>().firstOrNull : null;
  final locale = (first?['locale'] as String? ?? 'fr').toLowerCase();
  return locale.startsWith('fr') ? 'VF' : locale.toUpperCase();
}
