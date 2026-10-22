import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'svtplay_api.dart';
import 'svtplay_dates.dart';
import 'svtplay_mapper.dart';
import 'svtplay_numbering.dart';
import 'svtplay_queries.dart';

const _showTypes = {'TvSeries', 'TvShow', 'KidsTvShow'};

/// One season as the catalogue states it, reduced to the episodes that can be played now.
typedef _Season = ({Map<String, dynamic> raw, int number, List<Map<String, dynamic>> episodes});

/// Resolves titles and the show -> season -> episode structure from catalogue detail pages.
///
/// A season ref is `<show id>/<season id>`. A series is read from one detail page that carries every season and
/// episode. Single programmes have one pseudo-season and are movies, so they have no children here.
class SvtPlayCatalog {
  final SvtPlayApi _api;
  final SvtPlayMapper _mapper;
  final DateTime Function() _now;

  SvtPlayCatalog(this._api, this._mapper, this._now);

  /// A show, movie, or episode (with its show and season when the show page lists it), or a season.
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (id.contains('/')) return (await seasons(id.split('/').first)).where((s) => s.ref == ref).firstOrNull;

    final page = await _details(id);
    if (page == null) return null;
    final item = page['item'] as Map<String, dynamic>;
    if (item['__typename'] == 'Episode') return _episodeWithContext(page, item);
    return _mapper.fromDetails(page);
  }

  Future<List<ReplayTitle>> seasons(String showId) async {
    final page = await _details(showId);
    final show = page == null ? null : _mapper.fromDetails(page);
    if (page == null || show == null || show.kind != ReplayKind.show) return const [];

    return [for (final season in _playableSeasons(page['item'] as Map<String, dynamic>)) _season(season, show)];
  }

  ReplayTitle _season(_Season season, ReplayTitle show) {
    final ref = _seasonRef(show.ref, season.raw);
    _mapper.inheritRestrictions(ref, show.ref);
    return ReplayTitle(
      ref: ref,
      kind: ReplayKind.season,
      title: _seasonName(season),
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: season.number,
      childCount: season.episodes.length,
      showRef: show.ref,
      showTitle: show.title,
      availability: show.availability,
    );
  }

  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final parts = seasonRef.nativeId.split('/');
    if (parts.length != 2) return const [];
    final page = await _details(parts.first);
    final show = page == null ? null : _mapper.fromDetails(page);
    if (page == null || show == null) return const [];

    final season = _playableSeasons(page['item'] as Map<String, dynamic>).where((s) => s.raw['id'] == parts[1]);
    if (season.isEmpty) return const [];
    final context = SvtContext(
      show: show.ref,
      showTitle: show.title,
      season: seasonRef,
      seasonNumber: season.first.number,
    );
    return [
      for (final numbered in svtNumberEpisodes(season.first.episodes))
        ?_mapper.title({...numbered.episode, '__typename': 'Episode'}, context: context, number: numbered.number),
    ];
  }

  Future<Map<String, dynamic>?> _details(String id) async {
    final data = await _api.query(svtDetailsQuery, variables: {'id': id}, ttl: SvtPlayApi.detailsTtl);
    final page = data['detailsPage'];
    if (page is! Map<String, dynamic> || page['item'] is! Map<String, dynamic>) return null;
    return page;
  }

  /// Seasons oldest first, each with the episodes that are inside their availability window. Empty ones are dropped.
  List<_Season> _playableSeasons(Map<String, dynamic> item) {
    if (!_showTypes.contains(item['__typename'])) return const [];
    final raw = [
      for (final season in (item['seasons'] as List? ?? const []).whereType<Map<String, dynamic>>())
        if (_playableEpisodes(season).isNotEmpty) season,
    ];
    final numbers = svtSeasonNumbers(raw);
    final seasons = [
      for (var i = 0; i < raw.length; i++) (raw: raw[i], number: numbers[i], episodes: _playableEpisodes(raw[i])),
    ];
    seasons.sort((a, b) => a.number.compareTo(b.number));
    return seasons;
  }

  /// Future-dated episodes are listed by the catalogue (a news show announces weeks ahead) but cannot be played.
  List<Map<String, dynamic>> _playableEpisodes(Map<String, dynamic> season) {
    final now = _now();
    return [
      for (final episode in (season['episodes'] as List? ?? const []).whereType<Map<String, dynamic>>())
        if (_isInWindow(episode, now)) episode,
    ];
  }

  bool _isInWindow(Map<String, dynamic> episode, DateTime now) {
    final from = svtDate(episode['validFrom']);
    final until = svtDate(episode['validTo']);
    return (from == null || !from.isAfter(now)) && (until == null || until.isAfter(now));
  }

  Future<ReplayTitle?> _episodeWithContext(Map<String, dynamic> page, Map<String, dynamic> item) async {
    final episode = _mapper.fromDetails(page);
    final showId = (item['parent'] as Map?)?['svtId'] as String?;
    if (episode == null || showId == null) return episode;

    for (final season in await seasons(showId)) {
      final inSeason = (await episodes(season.ref)).where((e) => e.ref == episode.ref);
      if (inSeason.isNotEmpty) return inSeason.first.filledFrom(episode);
    }
    return episode;
  }

  ReplayRef _seasonRef(ReplayRef show, Map<String, dynamic> season) => svtPlayRef('${show.nativeId}/${season['id']}');

  String _seasonName(_Season season) {
    final name = (season.raw['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? 'Säsong ${season.number}' : name;
  }
}
