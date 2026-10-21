import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import '../dailymotion/dailymotion_resolver.dart';
import 'publicsenat_api.dart';
import 'publicsenat_catalog.dart';
import 'publicsenat_categories.dart';
import 'publicsenat_images.dart';
import 'publicsenat_mapper.dart';
import 'publicsenat_models.dart';
import 'publicsenat_refs.dart';
import 'publicsenat_search.dart';
import 'publicsenat_seasons.dart';

/// Public Sénat: the programme catalogue comes from the channel's site, video playback from Dailymotion.
///
/// Playback needs a [DailymotionResolver]. Without one every episode answers "unavailable" and the source
/// reports browse-only support, because Dailymotion's robots.txt disallows automated access to the
/// player-metadata endpoint a resolver has to call; the caller decides whether to supply one.
class PublicSenatProvider implements ReplayProvider {
  static const _pageSize = 12;
  static const _homeRailSize = 20;
  static const _playbackOff =
      'Playback is off: Dailymotion does not allow automated access to its player metadata (robots.txt).';

  final PublicSenatCatalog _catalog;
  final DailymotionResolver? resolver;

  PublicSenatProvider(MediaServerHttpClient http, {DailymotionResolver? resolver})
    : this.withApi(PublicSenatApi(http), resolver: resolver);

  /// Test seam: a provider over an API whose pacing and responses the caller controls.
  PublicSenatProvider.withApi(PublicSenatApi api, {this.resolver}) : _catalog = PublicSenatCatalog(api);

  @override
  ReplaySource get source => ReplaySource(
    id: publicSenatSourceId,
    name: 'Public Sénat',
    language: 'fr',
    support: resolver == null ? ReplayPlaybackSupport.browseOnly : ReplayPlaybackSupport.clear,
    listingPageSize: _pageSize,
  );

  @override
  Future<List<ReplayCategory>> categories() async => publicSenatCategories;

  @override
  Future<List<ReplayRail>> home() async {
    final latest = await _latestRail();
    final programmes = await _programmesRail();
    return [?latest, ?programmes];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final rail = switch (categoryId) {
      publicSenatLatestBrowseId => await _latestRail(),
      publicSenatProgrammesBrowseId => await _programmesRail(),
      publicSenatDocumentariesBrowseId => await _documentariesRail(),
      _ => null,
    };
    return rail == null ? const [] : [rail];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final titles = switch (browseId) {
      replayAllBrowseId || publicSenatProgrammesBrowseId => await _programmeTitles(),
      publicSenatLatestBrowseId => await _cardTitles(await _catalog.latest()),
      publicSenatDocumentariesBrowseId => await _documentaryTitles(),
      _ => const <ReplayTitle>[],
    };
    final from = page * _pageSize;
    if (page < 0 || from >= titles.length) return ReplayPage(titles: const [], totalCount: titles.length);
    final to = from + _pageSize > titles.length ? titles.length : from + _pageSize;
    return ReplayPage(titles: titles.sublist(from, to), totalCount: titles.length);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final shows = [
      for (final p in await _catalog.programmes())
        if (matchesQuery(query, [p.title])) publicSenatShowTitle(p),
    ];
    final cards = [
      for (final c in await _catalog.latest())
        if (matchesQuery(query, [c.title, c.showTitle])) c,
    ];
    return [...shows, ...await _cardTitles(cards)];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final target = parsePublicSenatId(ref.nativeId);
    if (target == null) return null;
    if (target.isShow) return _showTitle(target.slug);

    final show = await _catalog.show(target.slug);
    if (show == null) return null;
    final header = await _headerOf(show);
    if (target.seasonStartYear != null) {
      final season = show.seasons.where((s) => s.startYear == target.seasonStartYear).firstOrNull;
      return season == null ? null : publicSenatSeasonTitle(header, season);
    }
    return _episodeOf(show, header, target.videoId!);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final target = parsePublicSenatId(ref.nativeId);
    if (target == null || target.videoId != null) return const [];
    final show = await _catalog.show(target.slug);
    if (show == null) return const [];
    final header = await _headerOf(show);

    if (target.isShow) return [for (final s in show.seasons) publicSenatSeasonTitle(header, s)];
    final season = show.seasons.where((s) => s.startYear == target.seasonStartYear).firstOrNull;
    if (season == null) return const [];
    final episodes = season.episodes.any((e) => e.number != null) ? season.episodes : season.episodes.reversed;
    return [for (final e in episodes) _episodeTitle(e, header, season.startYear)];
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final videoId = parsePublicSenatId(ref.nativeId)?.videoId;
    if (videoId == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    final active = resolver;
    if (active == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: _playbackOff);
    return active.resolve(videoId);
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => publicSenatImageUrl(reference, width: width);

  @override
  bool ownsImage(String reference) => isPublicSenatImage(reference);

  @override
  void close() {}

  Future<ReplayRail?> _latestRail() async {
    final cards = (await _catalog.latest()).take(_homeRailSize).toList();
    if (cards.isEmpty) return null;
    return ReplayRail(
      id: publicSenatLatestBrowseId,
      title: 'Derniers replays',
      titles: await _cardTitles(cards),
      moreBrowseId: publicSenatLatestBrowseId,
    );
  }

  Future<ReplayRail?> _programmesRail() async {
    final titles = await _programmeTitles();
    if (titles.isEmpty) return null;
    return ReplayRail(id: publicSenatProgrammesBrowseId, title: 'Programmes', titles: titles);
  }

  Future<ReplayRail?> _documentariesRail() async {
    final titles = await _documentaryTitles();
    if (titles.isEmpty) return null;
    return ReplayRail(
      id: publicSenatDocumentariesBrowseId,
      title: 'Documentaires',
      titles: titles.take(_homeRailSize).toList(),
      moreBrowseId: publicSenatDocumentariesBrowseId,
    );
  }

  Future<List<ReplayTitle>> _programmeTitles() async => [
    for (final p in await _catalog.programmes()) publicSenatShowTitle(p),
  ];

  Future<List<ReplayTitle>> _documentaryTitles() async {
    final show = await _catalog.show(publicSenatDocumentarySlug);
    return show == null ? const [] : _cardTitles(show.cards);
  }

  /// Cards found outside a season grouping, such as the newest-videos page. They get the programme's
  /// canonical name when the index knows it.
  Future<List<ReplayTitle>> _cardTitles(List<PsCard> cards) async {
    final names = {for (final p in await _catalog.programmes()) p.slug: p.title};
    return [
      for (final c in cards) publicSenatEpisodeTitle(c, showTitle: names[c.showSlug] ?? c.showTitle ?? c.showSlug),
    ];
  }

  Future<ReplayTitle?> _showTitle(String slug) async {
    final page = await _catalog.firstPage(slug);
    if (page == null) return null;
    final programme = await _catalog.programme(slug) ?? PsProgramme(slug: slug, title: page.title ?? slug);
    return publicSenatShowTitle(programme, page: page);
  }

  Future<ReplayTitle> _headerOf(PsShow show) async {
    final programme =
        await _catalog.programme(show.slug) ?? PsProgramme(slug: show.slug, title: show.page.title ?? show.slug);
    return publicSenatShowTitle(programme, page: show.page, seasonCount: show.seasons.length);
  }

  ReplayTitle _episodeTitle(PsEpisode episode, ReplayTitle header, int seasonStart) =>
      publicSenatEpisodeTitle(episode.card, showTitle: header.title, seasonStart: seasonStart, number: episode.number);

  ReplayTitle? _episodeOf(PsShow show, ReplayTitle header, String videoId) {
    for (final season in show.seasons) {
      for (final episode in season.episodes) {
        if (episode.card.videoId == videoId) return _episodeTitle(episode, header, season.startYear);
      }
    }
    return null;
  }
}
