import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'lrt_dates.dart';
import 'lrt_models.dart';
import 'lrt_numbering.dart';
import 'lrt_refs.dart';

/// Where a recording was found, so it knows its programme and season.
class LrtContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const LrtContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = LrtContext();
}

/// A recording as an episode, or as a movie when [kind] says so. Parents come from [context] first and from what the
/// recording itself names second. A recording whose rights ended is marked expired.
ReplayTitle lrtRecordingTitle(
  LrtRecording recording, {
  LrtContext context = LrtContext.none,
  ReplayKind? kind,
  int? episodeNumber,
  DateTime? now,
}) {
  final showSlug = recording.showSlug;
  final seasonSlug = recording.seasonSlug;
  final show = context.show ?? (showSlug == null ? null : lrtShowRef(showSlug));
  final season = context.season ?? (showSlug == null || seasonSlug == null ? null : lrtSeasonRef(showSlug, seasonSlug));
  final until = recording.availableUntil;
  final published = recording.published;
  return ReplayTitle(
    ref: lrtRecordingRef(recording.postId),
    kind: kind ?? (recording.isMovie ? ReplayKind.movie : ReplayKind.episode),
    title: recording.title,
    subtitle: recording.subtitle ?? (published == null ? null : lrtLocalStamp(published)),
    summary: recording.summary,
    posterUrl: recording.imageTemplate,
    backdropUrl: recording.imageTemplate,
    durationSeconds: recording.durationSeconds,
    year: published?.year,
    contentRating: recording.ageRating,
    airDate: published,
    availableUntil: until,
    availability: until != null && until.isBefore(now ?? DateTime.now())
        ? ReplayAvailability.expired
        : ReplayAvailability.playable,
    seasonNumber: context.seasonNumber,
    episodeNumber: episodeNumber,
    showRef: show,
    showTitle: context.showTitle ?? recording.showTitle,
    seasonRef: season,
  );
}

/// Cards for a row, in the feed's order and cut to [limit] when one is given.
List<ReplayTitle> lrtRowTitles(List<LrtRecording> recordings, {ReplayKind? kind, int? limit}) {
  final titles = [for (final r in recordings) lrtRecordingTitle(r, kind: kind)];
  return limit == null ? titles : titles.take(limit).toList();
}

ReplayTitle lrtProgrammeTitle(LrtProgramme programme) => ReplayTitle(
  ref: lrtShowRef(programme.slug),
  kind: ReplayKind.show,
  title: programme.title,
  posterUrl: programme.imageTemplate,
  backdropUrl: programme.imageTemplate,
);

ReplayTitle lrtShowTitle(LrtShowPage page) => ReplayTitle(
  ref: lrtShowRef(page.slug),
  kind: ReplayKind.show,
  title: page.title,
  summary: page.summary,
  posterUrl: page.imageTemplate,
  backdropUrl: page.imageTemplate,
  childCount: page.seasons.isEmpty ? 1 : page.seasons.length,
);

/// The seasons of a programme, oldest first and numbered from 1. A programme that lists none gets one season that
/// stands for all its recordings.
List<ReplayTitle> lrtSeasonTitles(LrtShowPage page) {
  final ordered = lrtOrderSeasons(page.seasons);
  final show = lrtShowRef(page.slug);
  if (ordered.isEmpty) {
    return [
      ReplayTitle(
        ref: lrtSeasonRef(page.slug, lrtAllVideosSeason),
        kind: ReplayKind.season,
        title: page.title,
        posterUrl: page.imageTemplate,
        backdropUrl: page.imageTemplate,
        seasonNumber: 1,
        childCount: page.episodeTotal,
        showRef: show,
        showTitle: page.title,
      ),
    ];
  }
  return [
    for (var i = 0; i < ordered.length; i++)
      ReplayTitle(
        ref: lrtSeasonRef(page.slug, ordered[i].slug),
        kind: ReplayKind.season,
        title: ordered[i].title,
        posterUrl: page.imageTemplate,
        backdropUrl: page.imageTemplate,
        year: lrtSeasonYear(ordered[i].title),
        seasonNumber: i + 1,
        childCount: ordered.length == 1 ? page.episodeTotal : null,
        showRef: show,
        showTitle: page.title,
      ),
  ];
}
