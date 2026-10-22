import '../../model/replay_title.dart';
import 'nrktv_dates.dart';
import 'nrktv_geo.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_mapper.dart';
import 'nrktv_people.dart';
import 'nrktv_text.dart';

final _monthSeason = RegExp(r'^\d{6}$');

/// A programme page joined with the player's metadata, as a movie or, when the metadata names a series, an episode.
///
/// The programme page does not know its series, so the metadata decides the kind. Season ids tell which numbering a
/// series uses: "1".."99" is a counted season whose episode titles start with their number, a six-digit id is a
/// month of a news series whose titles name a day of the week.
ReplayTitle nrkProgram(String programId, Map<String, dynamic> page, Map<String, dynamic>? metadata, DateTime now) {
  final information = page['programInformation'] as Map? ?? const {};
  final more = page['moreInformation'] as Map? ?? const {};
  final titles = information['titles'] as Map? ?? const {};
  final series = metadata?['series'] as Map?;
  final seriesId = series?['id'] as String?;
  final seasonId = series?['seasonId'] as String?;
  final seasonNumber = seasonId == null ? null : int.tryParse(seasonId);
  final people = nrkPeople(page['contributors']);
  final rights = more['usageRights'];
  final category = (more['category'] as Map?)?['displayValue'] as String?;
  final summary = nrkPlainText(titles['subtitle'] as String? ?? '');
  final rawTitle = (titles['title'] as String? ?? programId).trim();
  final counted = seasonNumber != null && seasonNumber < 100;
  final number = counted ? nrkNumberPrefix(rawTitle)?.number : null;

  return ReplayTitle(
    ref: nrkProgramRef(programId),
    kind: seriesId == null ? ReplayKind.movie : ReplayKind.episode,
    title: _title(rawTitle, number, seasonId, more['releaseDateOnDemand']),
    summary: summary.isEmpty ? null : summary,
    backdropUrl: nrkImageRef(information['image'] ?? page['backdropImage']),
    durationSeconds: ((more['duration'] as Map?)?['seconds'] as num?)?.toInt(),
    year: (more['productionYear'] as num?)?.toInt(),
    genres: [?category],
    directors: people.directors,
    cast: people.cast,
    contentRating: nrkRating(more['legalAge']),
    airDate: nrkParseDate(more['releaseDateOnDemand']),
    availableUntil: nrkExpiry(((rights as Map?)?['to'] as Map?)?['date']),
    availability: nrkAvailability({'usageRights': rights, 'availability': information['availability']}, now),
    seasonNumber: seasonNumber,
    episodeNumber: number,
    showRef: seriesId == null ? null : nrkShowRef(seriesId),
    showTitle: seriesId == null ? null : ((metadata?['preplay'] as Map?)?['titles'] as Map?)?['title'] as String?,
    seasonRef: seriesId == null || seasonId == null || seasonId.isEmpty ? null : nrkSeasonRef(seriesId, seasonId),
  );
}

/// The geographic flag on a programme page.
bool? nrkProgramNorwayOnly(Map<String, dynamic> page) =>
    nrkNorwayOnly((page['moreInformation'] as Map?)?['usageRights']);

String _title(String raw, int? number, String? seasonId, Object? released) {
  if (seasonId != null && _monthSeason.hasMatch(seasonId)) return nrkNewsTitle(raw, nrkLocalDate(released));
  return nrkEpisodeTitle(raw, number: number);
}
