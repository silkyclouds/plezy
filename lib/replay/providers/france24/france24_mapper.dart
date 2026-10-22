import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'france24_ids.dart';
import 'france24_models.dart';
import 'france24_numbering.dart';
import 'france24_playback.dart';

/// A programme as a show.
ReplayTitle france24Show(France24Programme programme) {
  final id = France24Id.show(programme.nid);
  return ReplayTitle(
    ref: id.ref,
    kind: ReplayKind.show,
    title: programme.title,
    summary: _nonEmpty(htmlToText(programme.summaryHtml)),
    posterUrl: programme.squareImageUrl ?? programme.imageUrl,
    backdropUrl: programme.imageUrl ?? programme.squareImageUrl,
  );
}

/// One year of a programme as a season. The year is the season number.
ReplayTitle france24Season(ReplayTitle show, int year) {
  final id = France24Id.season(show.ref.nativeId, year);
  return ReplayTitle(
    ref: id.ref,
    kind: ReplayKind.season,
    title: '$year',
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: year,
    showRef: show.ref,
    showTitle: show.title,
  );
}

/// An edition as an episode of its programme, or null when it cannot be placed or played:
/// text-only articles have no video, and an edition without a programme or a date has no season.
ReplayTitle? france24Episode(France24Edition edition, DateTime now) {
  final video = edition.video;
  final programme = edition.programmeNid;
  final day = edition.day;
  if (video == null || video.formats.isEmpty || programme == null || day == null) return null;

  final id = France24Id.episode(programme, edition.nid);
  final season = France24Id.season(programme, day.year);
  return ReplayTitle(
    ref: id.ref,
    kind: ReplayKind.episode,
    title: edition.title,
    subtitle: edition.subtitle ?? video.label,
    summary: _nonEmpty(htmlToText(edition.summaryHtml)),
    backdropUrl: edition.imageUrl,
    durationSeconds: video.durationSeconds,
    year: day.year,
    genres: _genres(edition.section, edition.themes),
    cast: edition.people,
    airDate: edition.airDate,
    availableUntil: france24AvailableUntil(video, now),
    availability: france24Availability(video, now),
    seasonNumber: day.year,
    episodeNumber: france24DayOfYear(day),
    showRef: id.showRef,
    showTitle: edition.programmeTitle,
    seasonRef: season.ref,
  );
}

/// A video of the general feed, which belongs to no programme.
ReplayTitle? france24Clip(France24Video video, DateTime now) {
  if (video.formats.isEmpty) return null;
  final published = video.publishedAt;
  return ReplayTitle(
    ref: France24Id.clip(video.nid).ref,
    kind: ReplayKind.clip,
    title: video.title,
    subtitle: video.label,
    summary: _nonEmpty(htmlToText(video.summaryHtml)),
    backdropUrl: video.imageUrl,
    durationSeconds: video.durationSeconds,
    year: published?.year,
    cast: video.people,
    airDate: published,
    availableUntil: france24AvailableUntil(video, now),
    availability: france24Availability(video, now),
  );
}

List<ReplayTitle> france24Episodes(Iterable<France24Edition> editions, DateTime now) => [
  for (final edition in editions) ?france24Episode(edition, now),
];

List<ReplayTitle> france24Clips(Iterable<France24Video> videos, DateTime now) => [
  for (final video in videos) ?france24Clip(video, now),
];

List<String> _genres(String? section, List<String> themes) => {?section, ...themes}.toList();

String? _nonEmpty(String text) => text.isEmpty ? null : text;
