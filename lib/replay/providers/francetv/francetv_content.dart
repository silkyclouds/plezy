import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'francetv_mapper.dart' show franceTvPeople;
import 'francetv_numbering.dart';
import 'francetv_refs.dart';

/// Maps a raw content record to a title, for a video that was opened without having been seen in a list.
///
/// The record has no usable artwork address, so the title has none; the list that showed it did.
ReplayTitle? franceTvTitleFromContent(Map<String, dynamic> content, String streamId, {DateTime? now}) {
  final media = _mainMedia(content);
  if (media == null || media['si_id'] != streamId) return null;
  final program = _rootProgram(content);
  final numbers = franceTvNumbers({
    'season': content['saison'],
    'episode': content['episode'],
    'title': content['title'],
  });
  final isEpisode = content['type'] == 'integrale' && (program != null || numbers.episode != null);
  final until = _replayEnd(media);
  final programPath = (program?['url_complete'] as String?)?.replaceAll('/', '_');

  return ReplayTitle(
    ref: franceTvVideoRef(streamId, (content['id'] as num?)?.toInt()),
    kind: isEpisode ? ReplayKind.episode : ReplayKind.movie,
    title: (content['title'] as String?)?.trim() ?? streamId,
    subtitle: _text(content['headline_title']),
    summary: _text(content['description']) ?? _text(content['medium_description']),
    durationSeconds: (media['duration'] as num?)?.toInt(),
    year: (content['production_year'] as num?)?.toInt(),
    directors: franceTvPeople(content['director']),
    cast: franceTvPeople(content['casting']),
    contentRating: media['rating_csa_code'] as String?,
    availableUntil: until,
    availability: until != null && until.isBefore(now ?? DateTime.now())
        ? ReplayAvailability.expired
        : ReplayAvailability.playable,
    seasonNumber: isEpisode ? numbers.season : null,
    episodeNumber: isEpisode ? numbers.episode : null,
    showRef: isEpisode && programPath != null ? franceTvShowRef(programPath) : null,
    showTitle: isEpisode ? (program?['label'] as String?) : null,
  );
}

Map<String, dynamic>? _mainMedia(Map<String, dynamic> content) {
  for (final link in (content['content_has_medias'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    if (link['type'] == 'main' && link['media'] is Map<String, dynamic>) return link['media'] as Map<String, dynamic>;
  }
  return null;
}

Map<String, dynamic>? _rootProgram(Map<String, dynamic> content) {
  for (final link in (content['content_has_taxonomys'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final taxonomy = link['taxonomy'];
    if (link['type'] == 'program' && taxonomy is Map<String, dynamic> && taxonomy['is_root'] == true) return taxonomy;
  }
  return null;
}

/// The latest end of a free replay version; the media's own end date is the broadcast window.
DateTime? _replayEnd(Map<String, dynamic> media) {
  DateTime? latest;
  for (final version in (media['versions'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    if (version['class'] != 'free') continue;
    final end = DateTime.tryParse(version['end_date'] as String? ?? '')?.toUtc();
    if (end != null && (latest == null || end.isAfter(latest))) latest = end;
  }
  return latest;
}

String? _text(Object? html) {
  final text = htmlToText(html is String ? html : null);
  return text.isEmpty ? null : text;
}
