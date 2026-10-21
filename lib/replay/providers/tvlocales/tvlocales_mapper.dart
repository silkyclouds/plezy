import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'freecaster_player.dart';
import 'tvlocales_ids.dart';
import 'tvlocales_models.dart';
import 'tvlocales_numbering.dart';
import 'tvlocales_station.dart';

/// The show an episode or season is listed under.
class TvShowInfo {
  final String slug;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;

  const TvShowInfo({required this.slug, required this.title, this.posterUrl, this.backdropUrl});

  factory TvShowInfo.fromPage(String slug, TvShowPage page) => TvShowInfo(
    slug: slug,
    title: page.title.isEmpty ? slug : page.title,
    posterUrl: page.posterUrl,
    backdropUrl: page.backdropUrl,
  );
}

/// Builds the neutral titles of one station from what its parsers read.
class TvLocalesMapper {
  final TvLocalesStation station;

  const TvLocalesMapper(this.station);

  ReplayRef refOf(TvLocalesId id) => ReplayRef(station.id, id.nativeId);

  ReplayTitle showFromCard(TvShowCard card) => ReplayTitle(
    ref: refOf(TvLocalesId.show(card.slug)),
    kind: ReplayKind.show,
    title: card.title,
    posterUrl: card.imageUrl,
  );

  ReplayTitle showFromPage(String slug, TvShowPage page, {int? seasonCount}) => ReplayTitle(
    ref: refOf(TvLocalesId.show(slug)),
    kind: ReplayKind.show,
    title: page.title.isEmpty ? slug : page.title,
    summary: page.summary,
    posterUrl: page.posterUrl,
    backdropUrl: page.backdropUrl,
    childCount: seasonCount,
  );

  /// A season of [show]. The site's filter gives the label; without one the whole list is a single season.
  ReplayTitle season(TvShowInfo show, {required String facet, required String label, required int number}) =>
      ReplayTitle(
        ref: refOf(TvLocalesId.season(show.slug, facet)),
        kind: ReplayKind.season,
        title: label,
        posterUrl: show.posterUrl,
        backdropUrl: show.backdropUrl,
        seasonNumber: number,
        showRef: refOf(TvLocalesId.show(show.slug)),
        showTitle: show.title,
      );

  /// An episode from a show page, placed in the season whose list it came from, if it came from one.
  ReplayTitle episodeFromCard(
    TvShowInfo show,
    TvLocalesId id,
    TvEpisodeCard card, {
    String? facet,
    int? seasonNumber,
  }) => ReplayTitle(
    ref: refOf(id),
    kind: ReplayKind.episode,
    title: card.title,
    backdropUrl: card.imageUrl,
    durationSeconds: card.durationSeconds,
    airDate: card.airDate,
    seasonNumber: seasonNumber,
    episodeNumber: deriveEpisodeNumber(card.title),
    showRef: refOf(TvLocalesId.show(show.slug)),
    showTitle: show.title,
    seasonRef: facet == null ? null : refOf(TvLocalesId.season(show.slug, facet)),
  );

  /// A single episode from its own page, with the video's own duration and poster when Freecaster gave them.
  ReplayTitle episodeFromPage(TvLocalesId id, TvEpisodePage page, {FreecasterVideo? video, ReplayTitle? listed}) {
    final title = page.title ?? listed?.title ?? id.nativeId;
    return ReplayTitle(
      ref: refOf(id),
      kind: ReplayKind.episode,
      title: title,
      summary: page.summary,
      backdropUrl: video?.poster ?? page.imageUrl ?? listed?.backdropUrl,
      durationSeconds: video?.durationSeconds ?? page.durationSeconds ?? listed?.durationSeconds,
      airDate: page.airDate ?? listed?.airDate,
      seasonNumber: listed?.seasonNumber,
      episodeNumber: deriveEpisodeNumber(title),
      showRef: refOf(TvLocalesId.show(id.showSlug)),
      showTitle: page.showName ?? listed?.showTitle,
      seasonRef: listed?.seasonRef,
    );
  }
}
