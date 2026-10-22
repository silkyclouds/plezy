import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_api.dart';
import 'ardmediathek_json.dart';
import 'ardmediathek_mapper.dart';
import 'ardmediathek_numbering.dart';
import 'ardmediathek_refs.dart';

const _seriesCore = 'SEASON_SERIES';
const _pageSize = 100;
// A show can hold thousands of daily editions; the newest few hundred are what a viewer scrolls through.
const _maxPages = 3;

/// Resolves the show -> season -> episode structure of ARD groupings.
///
/// A season ref is `show/{id}/{number}`. Shows without numbered seasons, magazines, films with their extras and
/// daily programmes get one synthetic season, `show/{id}/all`, so every show has the same two levels.
class ArdMediathekCatalog {
  final ArdMediathekApi _api;
  final DateTime Function() _clock;

  ArdMediathekCatalog(this._api, this._clock);

  Future<ReplayTitle?> show(String showId) async => ardShowFromGrouping(await _api.grouping(showId), showId);

  Future<List<ReplayTitle>> seasons(String showId) async {
    final page = await _api.grouping(showId);
    final show = ardShowFromGrouping(page, showId);
    if (show == null) return const [];
    final numbers = ardText(page['coreAssetType']) == _seriesCore ? await _seasonNumbers(showId) : const <int>[];
    if (numbers.isEmpty) return [_season(show, showId, ardAllVideosSeason, 1, 'Alle Videos')];
    return [for (final number in numbers) _season(show, showId, '$number', number, 'Staffel $number')];
  }

  Future<ReplayTitle?> season(ReplayRef ref) async {
    final target = ardTarget(ref);
    if (target is! ArdSeasonTarget) return null;
    final seasons = await this.seasons(target.showId);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }

  /// Episodes of a season, without extras, other-language copies and ARTE content.
  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final target = ardTarget(seasonRef);
    if (target is! ArdSeasonTarget) return const [];
    final show = ardShowFromGrouping(await _api.grouping(target.showId), target.showId);
    if (show == null) return const [];

    final number = int.tryParse(target.season);
    final context = ArdContext(show: show.ref, showTitle: show.title, season: seasonRef, seasonNumber: number ?? 1);
    final episodes = <ReplayTitle>[];
    final seen = <ReplayRef>{};
    for (var page = 0; page < _maxPages; page++) {
      final widget = await _api.showEpisodes(target.showId, season: number, page: page, size: _pageSize);
      final total = ardInt(ardMap(widget['pagination'])?['totalElements']) ?? 0;
      for (final title in _titlesOf(widget, context)) {
        if (title.kind != ReplayKind.clip && seen.add(title.ref)) episodes.add(title);
      }
      if ((page + 1) * _pageSize >= total) break;
    }
    return _inOrder(episodes);
  }

  List<ReplayTitle> _titlesOf(Map<String, dynamic> widget, ArdContext context) => [
    for (final teaser in ardMaps(widget['teasers'])) ?ardTitleFromTeaser(teaser, context: context, now: _clock()),
  ];

  // The gateway has no season list. Every episode card carries its show's `availableSeasons`, so a few cards are
  // enough; the numbers in the titles are the fallback.
  Future<List<int>> _seasonNumbers(String showId) async {
    final widget = await _api.showEpisodes(showId, size: 6);
    final teasers = ardMaps(widget['teasers']);
    for (final teaser in teasers) {
      final listed = ardSeasonNumbers(ardMap(teaser['show'])?['availableSeasons']);
      if (listed.isNotEmpty) return listed;
    }
    final fromTitles = {for (final teaser in teasers) ?ardEpisodeTitle(ardText(teaser['longTitle']) ?? '').season};
    return fromTitles.toList()..sort();
  }

  ReplayTitle _season(ReplayTitle show, String showId, String id, int number, String title) => ReplayTitle(
    ref: ardSeasonRef(showId, id),
    kind: ReplayKind.season,
    title: title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: number,
    showRef: show.ref,
    showTitle: show.title,
  );

  // Episodes keep the gateway's order unless every one of them is numbered, in which case they run from first to last.
  List<ReplayTitle> _inOrder(List<ReplayTitle> episodes) {
    if (episodes.any((e) => e.episodeNumber == null)) return episodes;
    return [...episodes]..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
  }
}
