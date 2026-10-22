import '../../model/replay_title.dart';
import 'nhkworld_availability.dart';
import 'nhkworld_ids.dart';
import 'nhkworld_images.dart';
import 'nhkworld_numbering.dart';

/// Maps an episode or a clip of the catalogue.
///
/// [episodeNumber] is the number the season it sits in gave it; without one the number in the id is used, which is
/// right only when the whole season is not at hand.
ReplayTitle nhkEpisodeTitle(Map<String, dynamic> item, {required DateTime now, int? episodeNumber}) {
  final id = item['id'] as String;
  final isClip = item['type'] == 'VideoClip';
  final program = item['video_program'] as Map<String, dynamic>?;
  final programId = program?['id'] as String?;
  final showTitle = _text(program?['title']);
  final video = item['video'] as Map<String, dynamic>?;
  final year = nhkSeasonYear(item, now);

  return ReplayTitle(
    ref: isClip ? nhkClipRef(id) : nhkEpisodeRef(id),
    kind: isClip ? ReplayKind.clip : ReplayKind.episode,
    title: _text(item['title']) ?? showTitle ?? id,
    summary: nhkSummary(item),
    backdropUrl: nhkPickImage(item['images'], minWidth: 700),
    durationSeconds: (video?['duration'] as num?)?.toInt(),
    year: nhkAirDate(item)?.year,
    genres: _names(item['categories']),
    airDate: nhkAirDate(item),
    availableUntil: nhkParseDate(video?['expired_at']),
    availability: nhkAvailability(video, now),
    seasonNumber: isClip || programId == null ? null : year,
    episodeNumber: isClip ? null : episodeNumber ?? nhkOfficialNumber(id),
    showRef: programId == null ? null : nhkShowRef(programId),
    showTitle: showTitle,
    seasonRef: isClip || programId == null ? null : nhkSeasonRef(programId, year),
  );
}

/// A programme as a show. Programmes with no episode online are filtered out by the caller.
ReplayTitle nhkShowTitle(Map<String, dynamic> program) {
  final logo = ((program['hero'] as Map?)?['pc'] as Map?)?['logo'] as Map?;
  final images = program['images'] as Map<String, dynamic>?;
  return ReplayTitle(
    ref: nhkShowRef(program['id'] as String),
    kind: ReplayKind.show,
    title: _text(program['title']) ?? program['id'] as String,
    summary: _text(program['description']),
    posterUrl: nhkPickImage(images?['portrait'], minWidth: 450),
    backdropUrl: nhkPickImage(images?['landscape'], minWidth: 1400),
    logoUrl: logo?['url'] is String ? nhkWorldImageUrl(logo!['url'] as String) : null,
    genres: _names(program['categories']),
  );
}

/// The synopsis without the "*First broadcast on ..." line NHK puts first.
String? nhkSummary(Map<String, dynamic> item) {
  final text = _text(item['description']);
  if (text == null) return null;
  final lines = text.split('\n')..removeWhere((line) => line.trimLeft().startsWith('*First broadcast'));
  return _text(lines.join('\n'));
}

List<ReplayCategory> nhkCategories(Map<String, dynamic> page) => [
  for (final raw in (page['items'] as List? ?? const []).whereType<Map<String, dynamic>>())
    if (((raw['video_episodes'] as Map?)?['total'] as num? ?? 0) > 0)
      ReplayCategory(id: raw['id'] as String, title: raw['name'] as String),
];

/// Whether a programme has something to watch: broadcast-only and link-out programmes are left out.
bool nhkProgramHasVideo(Map<String, dynamic> program) =>
    ((program['video_episodes'] as Map?)?['total'] as num? ?? 0) > 0 && program['external_url'] == null;

List<String> _names(Object? entries) => [
  for (final entry in (entries as List? ?? const []).whereType<Map<String, dynamic>>()) ?_text(entry['name']),
];

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
