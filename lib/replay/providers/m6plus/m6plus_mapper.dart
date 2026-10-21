import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'm6plus_availability.dart';
import 'm6plus_dates.dart';
import 'm6plus_genres.dart';
import 'm6plus_images.dart';
import 'm6plus_numbering.dart';

const m6plusSourceId = 'm6plus';

/// Programme kinds that are one self-contained work when a single full video is available.
const _singleWorkTypes = {'film', 'telefilm', 'documentaire', 'spectacle', 'concert', 'reportage'};

/// Season keys that do not come from a season number.
const m6plusExtractsSeason = 'clips';
const m6plusPodcastsSeason = 'podcasts';
const m6plusOtherSeason = 'other';

ReplayRef m6plusRef(String nativeId) => ReplayRef(m6plusSourceId, nativeId);

/// Season key of a video inside its programme: `s3`, `other`, `clips` or `podcasts`.
String m6plusSeasonKey(String? videoType, int? season) => switch (videoType) {
  'vc' => m6plusExtractsSeason,
  'podcast' => m6plusPodcastsSeason,
  _ => season == null ? m6plusOtherSeason : 's$season',
};

int? m6plusInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value');

bool m6plusIsMovie(Map<String, dynamic> program) {
  final count = program['count'];
  if (count is! Map) return false;
  final type = (program['program_type_wording'] as Map?)?['code'];
  return m6plusInt(count['vi']) == 1 &&
      (m6plusInt(count['vc']) ?? 0) == 0 &&
      (m6plusInt(count['podcast']) ?? 0) == 0 &&
      _singleWorkTypes.contains(type);
}

/// A programme as a show, or as a movie when it holds one full video of a single-work kind.
ReplayTitle m6plusTitleFromProgram(Map<String, dynamic> program) {
  final images = program['images'];
  final backdrop = m6plusBackdrop(images);
  final count = program['count'];
  final hasFullVideos = count is Map && (m6plusInt(count['vi']) ?? 0) > 0;
  return ReplayTitle(
    ref: m6plusRef('${program['id']}'),
    kind: m6plusIsMovie(program) ? ReplayKind.movie : ReplayKind.show,
    title: (program['title'] as String? ?? '${program['id']}').trim(),
    summary: _summary(program['description'] as String?, program['summary'] as String?),
    posterUrl: m6plusPoster(images) ?? backdrop,
    backdropUrl: backdrop,
    logoUrl: m6plusLogo(images),
    year: int.tryParse('${program['year_production'] ?? program['year_copyright'] ?? ''}'),
    genres: m6plusGenres((program['neustar'] as Map?)?['category'] as String?),
    contentRating: _rating(program['csa']),
    airDate: m6plusDate(program['first_local_air_date']),
    availableUntil: hasFullVideos ? m6plusDate((program['publication_date_vi'] as Map?)?['date_end_max']) : null,
    availability: m6plusProgramAvailability(program),
  );
}

/// A video as an episode (full videos) or a clip (extracts and podcasts), or null when it has no id.
ReplayTitle? m6plusTitleFromVideo(Map<String, dynamic> video, {String? country, DateTime? now}) {
  final id = video['id'];
  if (id is! String || id.isEmpty) return null;
  final type = video['type'] as String?;
  final isEpisode = type == 'vi';
  final clip = _firstClip(video);
  final product = clip?['product'] as Map<String, dynamic>?;
  final info = m6plusEpisodeInfo(
    title: video['title'] as String? ?? id,
    season: m6plusInt(product?['season']),
    episode: m6plusInt(product?['episode']),
    seasonTitle: product?['season_title'] as String?,
  );
  final program = video['program'] as Map<String, dynamic>?;
  final programId = program?['id'];
  final seasonKey = m6plusSeasonKey(type, info.season);
  final image = m6plusBackdrop(video['images']) ?? m6plusBackdrop([video['display_image']]);

  return ReplayTitle(
    ref: m6plusRef(id),
    kind: isEpisode ? ReplayKind.episode : ReplayKind.clip,
    title: isEpisode ? info.title : (video['title'] as String? ?? id).trim(),
    summary: _summary(video['description'] as String?, product?['summary'] as String?),
    posterUrl: image,
    backdropUrl: image,
    durationSeconds: m6plusInt(video['duration']),
    contentRating: _rating(video['csa']),
    airDate: m6plusDate(product?['first_local_air_date']) ?? m6plusDate(video['publication_date']),
    availability: m6plusVideoAvailability(video, country: country, now: now),
    seasonNumber: isEpisode ? info.season : null,
    episodeNumber: isEpisode ? info.episode : null,
    showRef: programId == null ? null : m6plusRef('$programId'),
    showTitle: (program?['title'] as String?)?.trim(),
    seasonRef: programId == null ? null : m6plusRef('$programId/$seasonKey'),
  );
}

Map<String, dynamic>? _firstClip(Map<String, dynamic> video) {
  final clips = video['clips'];
  return clips is List && clips.isNotEmpty && clips.first is Map<String, dynamic>
      ? clips.first as Map<String, dynamic>
      : null;
}

String? _summary(String? primary, String? fallback) {
  final text = htmlToText(primary);
  if (text.isNotEmpty) return text;
  final other = htmlToText(fallback);
  return other.isEmpty ? null : other;
}

/// French age marks: "-10" for "forbidden under 10". All-audiences content has none.
String? _rating(Object? csa) {
  final age = csa is Map ? m6plusInt(csa['age']) : null;
  return age == null || age <= 0 ? null : '-$age';
}
