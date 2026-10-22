import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtveplay_dates.dart';
import 'rtveplay_ids.dart';
import 'rtveplay_images.dart';
import 'rtveplay_numbering.dart';
import 'rtveplay_text.dart';

/// `type.id` RTVE gives to a full-length video; trailers, clips and previews have other ids.
const rtveFullEpisodeType = 39816;

/// Where a video was found, so it knows its show and season without a second request.
class RtveContext {
  final ReplayRef? season;
  final int? seasonNumber;

  const RtveContext({this.season, this.seasonNumber});

  static const none = RtveContext();
}

/// A programme record as a show, or null when it has no id.
ReplayTitle? rtveShowFromProgram(Map<String, dynamic> program) {
  final id = rtveNonEmpty(program['id']?.toString());
  if (id == null) return null;
  final title = rtveNonEmpty(program['title']) ?? rtveNonEmpty(program['name']) ?? rtveNonEmpty(program['longTitle']);
  final seasons = (program['numSeasons'] as num?)?.toInt() ?? 0;
  return ReplayTitle(
    ref: rtveShowRef(id),
    kind: ReplayKind.show,
    title: title ?? id,
    summary: rtveSummary(program['longDescription'], program['description']),
    posterUrl: rtveProgramImage(program, rtvePosterFields),
    backdropUrl: rtveProgramImage(program, rtveBackdropFields),
    logoUrl: rtveLogo(program),
    year: _year(rtveParseDate(program['productionDate'])),
    genres: _genres(program),
    directors: rtveNames(program['director']),
    cast: rtveNames(program['casting']),
    contentRating: rtveContentRating(program['ageRange']),
    childCount: seasons > 0 ? seasons : null,
  );
}

/// A season of [show]. [orden] is RTVE's order, which is also the season number.
ReplayTitle? rtveSeasonFromItem(Map<String, dynamic> item, ReplayTitle show) {
  final id = rtveNonEmpty(item['id']?.toString());
  if (id == null) return null;
  final number = (item['orden'] as num?)?.toInt();
  final count = (item['numEpisodes'] as num?)?.toInt();
  return ReplayTitle(
    ref: rtveSeasonRef(_programId(show), id),
    kind: ReplayKind.season,
    title: rtveNonEmpty(item['longTitle']) ?? rtveNonEmpty(item['title']) ?? 'Temporada ${number ?? ''}'.trim(),
    summary: rtveSummary(item['description'], item['shortDescription']),
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: number,
    childCount: count != null && count > 0 ? count : null,
    showRef: show.ref,
    showTitle: show.title,
  );
}

/// The single season of a programme that RTVE does not split into seasons.
ReplayTitle rtveSyntheticSeason(ReplayTitle show) => ReplayTitle(
  ref: rtveSeasonRef(_programId(show), rtveAllEpisodesSeason),
  kind: ReplayKind.season,
  title: show.title,
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: 1,
  showRef: show.ref,
  showTitle: show.title,
);

/// A video record as an episode, a film or a clip, or null when it has no id.
ReplayTitle? rtveTitleFromVideo(Map<String, dynamic> video, {RtveContext context = RtveContext.none, DateTime? now}) {
  final id = rtveNonEmpty(video['id']?.toString());
  if (id == null) return null;
  final info = video['programInfo'] as Map<String, dynamic>?;
  final programId = rtveNonEmpty(info?['id']?.toString());
  final kind = _videoKind(video, info);
  final aired = rtveParseDate(video['dateOfEmission']) ?? rtveParseDate(video['publicationDate']);
  final frame = rtveVideoImage(id);
  final numbered = kind == ReplayKind.episode;
  return ReplayTitle(
    ref: rtveVideoRef(id),
    kind: kind,
    title: rtveNonEmpty(video['shortTitle']) ?? rtveNonEmpty(video['title']) ?? rtveNonEmpty(video['longTitle']) ?? id,
    summary: rtveSummary(video['description'], video['shortDescription']),
    posterUrl: frame,
    backdropUrl: frame,
    durationSeconds: _seconds(video['duration']),
    year: _year(aired),
    genres: _genres(video),
    directors: rtveNames(video['director']),
    cast: rtveNames(video['casting']),
    contentRating: rtveContentRating(video['ageRange']),
    airDate: aired,
    availableUntil: rtveParseDate(video['expirationDate']),
    availability: rtveAvailability(video, now ?? DateTime.now().toUtc()),
    seasonNumber: numbered ? context.seasonNumber ?? rtveSeasonNumber(video) : null,
    episodeNumber: numbered ? rtveEpisodeNumber(video) : null,
    showRef: programId == null ? null : rtveShowRef(programId),
    showTitle: rtveNonEmpty(info?['title']),
    seasonRef: programId == null ? null : context.season ?? _seasonOf(programId, video),
  );
}

/// What the catalogue says about a video's availability. It cannot see country or login limits: those only show when
/// the manifest is requested.
ReplayAvailability rtveAvailability(Map<String, dynamic> video, DateTime now) {
  if ((video['pubState'] as Map?)?['code'] == 'DESPU') return ReplayAvailability.expired;
  final end = rtveParseDate(video['expirationDate']);
  if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
  final start = rtveFromEpoch(video['publicationDateTimestamp']) ?? rtveParseDate(video['publicationDate']);
  if (start != null && start.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}

ReplayKind _videoKind(Map<String, dynamic> video, Map<String, dynamic>? info) {
  final typeId = ((video['type'] as Map?)?['id'] as num?)?.toInt();
  if (typeId != null && typeId != rtveFullEpisodeType) return ReplayKind.clip;
  final programType = (info?['programType'] as String? ?? '').toLowerCase();
  return programType.contains('películas') ? ReplayKind.movie : ReplayKind.episode;
}

ReplayRef _seasonOf(String programId, Map<String, dynamic> video) {
  final seasonId = video['temporadaId']?.toString();
  return rtveSeasonRef(programId, seasonId == null || seasonId.isEmpty ? rtveAllEpisodesSeason : seasonId);
}

String _programId(ReplayTitle show) => show.ref.nativeId.substring(1);

int? _year(DateTime? date) => date == null || date.year < 1900 ? null : date.year;

int? _seconds(Object? millis) {
  final value = millis is num ? millis : num.tryParse(millis?.toString() ?? '');
  return value == null || value <= 0 ? null : (value / 1000).round();
}

List<String> _genres(Map<String, dynamic> item) {
  final genres = item['generos'];
  if (genres is! List) return const [];
  final names = <String>{};
  for (final genre in genres.whereType<Map<String, dynamic>>()) {
    final name = rtveNonEmpty(genre['generoInf']);
    if (name != null) names.add(name);
  }
  return names.toList();
}
