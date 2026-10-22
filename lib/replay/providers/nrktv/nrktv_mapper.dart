import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_dates.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_json.dart';
import 'nrktv_numbering.dart';
import 'nrktv_people.dart';
import 'nrktv_text.dart';

/// The show and season an episode is mapped under.
class NrkSeasonContext {
  final ReplayRef showRef;
  final String showTitle;
  final String seriesType;
  final ReplayRef? seasonRef;
  final int? seasonNumber;

  const NrkSeasonContext({
    required this.showRef,
    required this.showTitle,
    required this.seriesType,
    this.seasonRef,
    this.seasonNumber,
  });
}

/// Whether a catalogue episode or programme can be played at [now], judged by its status and rights window.
/// The geographic flag is left to the forecast and to playback.
ReplayAvailability nrkAvailability(Map<String, dynamic> item, DateTime now) {
  final rights = item['usageRights'];
  final from = nrkParseDate(nrkField(nrkField(rights, 'from'), 'date'));
  final to = nrkExpiry(nrkField(nrkField(rights, 'to'), 'date'));
  if (to != null && !to.isAfter(now)) return ReplayAvailability.expired;
  final status = (item['availability'] as Map?)?['status'];
  return switch (status) {
    'available' => from != null && from.isAfter(now) ? ReplayAvailability.upcoming : ReplayAvailability.playable,
    'coming' => ReplayAvailability.upcoming,
    String() => ReplayAvailability.expired,
    _ => ReplayAvailability.playable,
  };
}

/// A series header as a show. [posterFrom] is a portrait picture to use, [seasons] the number of seasons it has.
ReplayTitle nrkShow(Map<String, dynamic> body, {required String seriesId, String? posterFrom, int? seasons}) {
  final type = body['seriesType'] as String?;
  final series = (body[type] ?? body['sequential'] ?? body['standard'] ?? body['news']) as Map? ?? const {};
  final titles = series['titles'] as Map? ?? const {};
  final summary = titles['subtitle'] as String? ?? '';
  final category = (series['category'] as Map?)?['name'] as String?;
  return ReplayTitle(
    ref: nrkShowRef(seriesId),
    kind: ReplayKind.show,
    title: (titles['title'] as String? ?? seriesId).trim(),
    summary: summary.trim().isEmpty ? null : nrkPlainText(summary),
    posterUrl: posterFrom,
    backdropUrl: nrkImageRef(series['image']),
    logoUrl: nrkImageRef(series['logoImage']),
    genres: [?category],
    childCount: seasons,
  );
}

/// One episode of a catalogue season (`episodes` or `instalments`).
ReplayTitle nrkEpisode(Map<String, dynamic> raw, NrkSeasonContext context, int number, DateTime now) {
  final titles = raw['titles'] as Map? ?? const {};
  final title = _episodeTitle(titles['title'] as String? ?? '', raw, context, number);
  final summary = nrkPlainText(titles['subtitle'] as String? ?? '');
  final people = nrkPeople(raw['contributors']);
  return ReplayTitle(
    ref: nrkProgramRef(raw['prfId'] as String),
    kind: ReplayKind.episode,
    title: title,
    summary: summary.isEmpty ? null : summary,
    backdropUrl: nrkImageRef(raw['image']),
    durationSeconds: (raw['durationInSeconds'] as num?)?.toInt(),
    year: (raw['productionYear'] as num?)?.toInt(),
    directors: people.directors,
    cast: people.cast,
    contentRating: nrkRating(raw['legalAge']),
    airDate: nrkParseDate(raw['releaseDateOnDemand']),
    availableUntil: nrkExpiry(nrkField(nrkField(raw['usageRights'], 'to'), 'date')),
    availability: nrkAvailability(raw, now),
    seasonNumber: context.seasonNumber,
    episodeNumber: number,
    showRef: context.showRef,
    showTitle: context.showTitle,
    seasonRef: context.seasonRef,
  );
}

String _episodeTitle(String raw, Map<String, dynamic> episode, NrkSeasonContext context, int number) {
  if (context.seriesType == 'news') return nrkNewsTitle(raw, nrkLocalDate(episode['releaseDateOnDemand']));
  return nrkEpisodeTitle(raw, number: nrkStatedNumber(episode) == number ? number : null);
}

/// The age shown in the catalogue ("9+", "A"), or null for news and other exempt programmes.
String? nrkRating(Object? legalAge) {
  final body = legalAge is Map ? legalAge['body'] : null;
  final rating = body is Map ? body['rating'] : null;
  final age = rating is Map ? rating['displayAge'] : null;
  return age is String && age.isNotEmpty ? age : null;
}
