import '../../model/replay_title.dart';
import 'publicsenat_models.dart';
import 'publicsenat_refs.dart';
import 'publicsenat_seasons.dart';

ReplayTitle publicSenatShowTitle(PsProgramme programme, {PsShowPage? page, int? seasonCount}) {
  final summary = page?.summary?.trim();
  return ReplayTitle(
    ref: publicSenatShowRef(programme.slug),
    kind: ReplayKind.show,
    title: programme.title,
    summary: summary == null || summary.isEmpty ? null : summary,
    posterUrl: programme.posterUrl,
    backdropUrl: page?.backdropUrl,
    childCount: seasonCount,
  );
}

ReplayTitle publicSenatSeasonTitle(ReplayTitle show, PsSeason season) {
  final slug = show.ref.nativeId;
  return ReplayTitle(
    ref: publicSenatSeasonRef(slug, season.startYear),
    kind: ReplayKind.season,
    title: season.startYear == 0 ? show.title : 'Saison ${season.startYear}-${season.startYear + 1}',
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: season.startYear,
    childCount: season.episodes.length,
    showRef: show.ref,
    showTitle: show.title,
  );
}

/// An episode card as a title. [seasonStart] and [number] come from the season grouping; without them the
/// season is read from the air date and the number is left out.
ReplayTitle publicSenatEpisodeTitle(PsCard card, {required String showTitle, int? seasonStart, int? number}) {
  final date = card.airDate;
  final start = seasonStart ?? (date == null ? null : broadcastSeasonStart(date));
  return ReplayTitle(
    ref: publicSenatEpisodeRef(card.showSlug, card.videoId),
    kind: ReplayKind.episode,
    title: card.title,
    subtitle: card.theme,
    posterUrl: card.imageUrl,
    backdropUrl: card.imageUrl,
    durationSeconds: card.durationSeconds,
    year: date?.year,
    genres: card.theme == null ? const [] : [card.theme!],
    airDate: date,
    seasonNumber: start,
    episodeNumber: number,
    showRef: publicSenatShowRef(card.showSlug),
    showTitle: showTitle,
    seasonRef: start == null ? null : publicSenatSeasonRef(card.showSlug, start),
  );
}
