import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'freecaster_player.dart';
import 'tvlocales_api.dart';
import 'tvlocales_ids.dart';
import 'tvlocales_mapper.dart';
import 'tvlocales_models.dart';
import 'tvlocales_numbering.dart';
import 'tvlocales_site.dart';
import 'tvlocales_station.dart';
import 'tvlocales_text.dart';

const _maxRememberedEpisodes = 400;
const _maxSearchResults = 60;

/// The show, season and episode structure of one station.
///
/// A show with a season filter on its site has one season per filter value. Every other show has a single
/// synthetic season, [TvLocalesId.allEpisodes], that holds all of its episodes.
class TvLocalesCatalog {
  final TvLocalesStation station;
  final TvLocalesSite _site;
  final FreecasterResolver _freecaster;
  final TvLocalesMapper _mapper;
  final Map<String, ReplayTitle> _seen = {};

  TvLocalesCatalog(this.station, this._site, this._freecaster) : _mapper = TvLocalesMapper(station);

  Future<List<ReplayTitle>> shows() async => [for (final card in await _site.showCards()) _mapper.showFromCard(card)];

  Future<ReplayTitle?> show(String slug) async {
    final page = await _showPage(slug);
    return page == null || page.title.isEmpty ? null : _mapper.showFromPage(slug, page);
  }

  /// The seasons of a show; empty when the show has no episode with a video.
  Future<List<ReplayTitle>> seasons(String slug) async {
    final page = await _showPage(slug);
    if (page == null) return const [];
    final info = TvShowInfo.fromPage(slug, page);
    if (page.seasons.isNotEmpty) {
      return [
        for (var i = 0; i < page.seasons.length; i++)
          _mapper.season(
            info,
            facet: page.seasons[i].facet,
            label: page.seasons[i].label,
            number: seasonNumberFromLabel(page.seasons[i].label, fallback: page.seasons.length - i),
          ),
      ];
    }
    if (page.episodes.isEmpty) return const [];
    return [_mapper.season(info, facet: TvLocalesId.allEpisodes, label: 'Tous les épisodes', number: 1)];
  }

  Future<ReplayTitle?> season(TvLocalesId id) async =>
      (await seasons(id.showSlug)).where((s) => s.ref == _mapper.refOf(id)).firstOrNull;

  /// The episodes of a season, newest first, over as many slices as the site allows.
  Future<List<ReplayTitle>> episodes(TvLocalesId season) async {
    final facet = season.seasonFacet!;
    final first = await _showPage(season.showSlug, facet: facet);
    if (first == null) return const [];
    final info = TvShowInfo.fromPage(season.showSlug, first);
    final number = _seasonNumber(first, facet);
    final titles = <ReplayTitle>[];
    final seen = <String>{};
    TvShowPage? page = first;
    for (var slice = 0; page != null; slice++) {
      final fresh = _titles(info, page.episodes, seen, facet: facet, seasonNumber: number);
      titles.addAll(fresh);
      // A slice that adds nothing means the site ignored the page number, so stop rather than repeat it.
      final more = fresh.isNotEmpty && page.hasNext && slice + 1 < _site.maxEpisodePages;
      page = more ? await _laterSlice(season.showSlug, facet, slice + 1) : null;
    }
    return _remember(titles);
  }

  /// An episode with the detail of its own page; null when the page is gone.
  Future<ReplayTitle?> episode(TvLocalesId id) async {
    final page = await episodePage(id);
    if (page == null) return null;
    final video = page.videoId == null ? null : await _optionalVideo(page.videoId!);
    return _mapper.episodeFromPage(id, page, video: video, listed: _seen[id.nativeId]);
  }

  Future<TvEpisodePage?> episodePage(TvLocalesId id) async {
    try {
      return await _site.episodePage(id.showSlug, id.episodePath!);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Shows whose name holds every word of the query, then the episodes already loaded that do.
  Future<List<ReplayTitle>> search(String query) async {
    final words = foldForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    bool matches(ReplayTitle t) {
      final name = foldForSearch(t.title);
      return words.every(name.contains);
    }

    final found = [...(await shows()).where(matches), ..._seen.values.where(matches)];
    return found.take(_maxSearchResults).toList();
  }

  /// The newest episodes of the station's news show, or null when it has none.
  Future<ReplayRail?> latest() async {
    final slug = station.latestShowSlug;
    final page = slug == null ? null : await _showPage(slug);
    if (slug == null || page == null) return null;
    final titles = _titles(TvShowInfo.fromPage(slug, page), page.episodes, <String>{});
    if (titles.isEmpty) return null;
    return ReplayRail(id: 'latest', title: '${page.title} : derniers épisodes', titles: _remember(titles));
  }

  Future<TvShowPage?> _showPage(String slug, {String? facet, int slice = 0}) async {
    try {
      final selected = facet == TvLocalesId.allEpisodes ? null : facet;
      return await _site.showPage(slug, seasonFacet: selected, page: slice);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// A slice after the first. The sites sometimes answer 500 for one slice of a long list, and the episodes
  /// already read are worth more than an error.
  Future<TvShowPage?> _laterSlice(String slug, String facet, int slice) async {
    try {
      return await _showPage(slug, facet: facet, slice: slice);
    } on MediaServerHttpException catch (e) {
      if ((e.statusCode ?? 0) >= 500) return null;
      rethrow;
    }
  }

  int _seasonNumber(TvShowPage page, String facet) {
    final index = page.seasons.indexWhere((s) => s.facet == facet);
    if (index < 0) return 1;
    return seasonNumberFromLabel(page.seasons[index].label, fallback: page.seasons.length - index);
  }

  /// Titles for the cards whose ids are not in [seen], which is updated.
  List<ReplayTitle> _titles(
    TvShowInfo show,
    List<TvEpisodeCard> cards,
    Set<String> seen, {
    String? facet,
    int? seasonNumber,
  }) {
    final titles = <ReplayTitle>[];
    for (final card in cards) {
      final id = TvLocalesId.tryParse('${show.slug}/${card.path}');
      if (id == null || !seen.add(id.nativeId)) continue;
      titles.add(_mapper.episodeFromCard(show, id, card, facet: facet, seasonNumber: seasonNumber));
    }
    return titles;
  }

  List<ReplayTitle> _remember(List<ReplayTitle> titles) {
    for (final title in titles) {
      _seen.remove(title.ref.nativeId);
      _seen[title.ref.nativeId] = title;
    }
    while (_seen.length > _maxRememberedEpisodes) {
      _seen.remove(_seen.keys.first);
    }
    return titles;
  }

  /// The player configuration only adds a duration and a poster, so a refusal leaves the page's own detail.
  Future<FreecasterVideo?> _optionalVideo(String videoId) async {
    try {
      return await _freecaster.video(videoId);
    } on TvLocalesRateLimitedException {
      return null;
    } on MediaServerHttpException {
      return null;
    }
  }
}
