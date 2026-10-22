import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'stvr_record.dart';
import 'stvr_refs.dart';

/// The show a recording belongs to, as a card. [ref] is the id the caller reached the show by, which can differ from
/// the recording's own series id.
ReplayTitle stvrShowFromRecord(StvrRecord record, {ReplayRef? ref}) {
  final name = record.showName;
  return ReplayTitle(
    ref: ref ?? stvrShowRef(record.series),
    kind: ReplayKind.show,
    title: name.base,
    summary: record.synopsis.isEmpty ? null : record.synopsis,
    posterUrl: record.image,
    backdropUrl: record.image,
  );
}

/// One recording as an episode. Lists that cannot count their recordings leave [episodeNumber] null.
ReplayTitle stvrEpisodeFromRecord(
  StvrRecord record, {
  ReplayRef? show,
  ReplayRef? season,
  int? seasonNumber,
  int? episodeNumber,
  DateTime? now,
}) {
  final name = record.showName;
  final air = record.air;
  final end = record.licenseEnd;
  final summary = record.description.isNotEmpty ? record.description : record.synopsis;
  return ReplayTitle(
    ref: stvrEpisodeRef(record.id, record.airDay),
    kind: ReplayKind.episode,
    title: record.subtitle.isEmpty ? name.base : record.subtitle,
    summary: summary.isEmpty ? null : summary,
    posterUrl: record.image,
    backdropUrl: record.image,
    year: air?.year,
    airDate: air,
    availableUntil: end,
    availability: _availability(air, end, now ?? DateTime.now().toUtc()),
    seasonNumber: seasonNumber ?? name.season ?? 1,
    episodeNumber: episodeNumber,
    showRef: show ?? stvrShowRef(record.series),
    showTitle: name.base,
    seasonRef: season ?? stvrSeasonRef(record.series, record.series),
  );
}

ReplayAvailability _availability(DateTime? air, DateTime? end, DateTime now) {
  if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
  if (air != null && air.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}
