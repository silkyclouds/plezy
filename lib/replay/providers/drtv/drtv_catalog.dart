import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'drtv_access.dart';
import 'drtv_api.dart';
import 'drtv_mapper.dart';
import 'drtv_refs.dart';

/// Resolves the show -> season -> episode structure of DR's catalogue.
///
/// DR opens a show on its newest season and lists the others in `show.seasons`. Long-running shows number their
/// seasons by year. A show DR does not split gets one synthetic season, `serie/{id}/alle`, so every show has two levels.
class DrtvCatalog {
  static const _maxContinuations = 10;

  final DrtvApi _api;
  final DrtvMapper _mapper;

  DrtvCatalog(this._api, this._mapper);

  Future<ReplayTitle?> show(String showId) async {
    final showJson = (await _open(drtvShowPath(showId)))?.show;
    return showJson == null ? null : _mapper.title(showJson);
  }

  Future<List<ReplayTitle>> seasons(String showId) async {
    final opened = await _open(drtvShowPath(showId));
    final showJson = opened?.show;
    final show = showJson == null ? null : _mapper.title(showJson);
    if (opened == null || showJson == null || show == null) return const [];

    final context = _contextOf(show, showJson);
    final listed = (showJson['seasons'] as Map<String, dynamic>?)?['items'];
    final raw = [
      if (listed is List && listed.isNotEmpty) ...listed else if (opened.item['type'] == 'season') opened.item,
    ].whereType<DrtvJson>().where((s) => s['availableEpisodeCount'] != 0).toList();

    final cards = <ReplayTitle>[];
    for (var i = 0; i < raw.length; i++) {
      final card = _mapper.title(raw[i], context: context, fallbackSeason: i + 1);
      if (card != null) cards.add(card);
    }
    if (cards.isEmpty) return [_syntheticSeason(show)];
    return _ordered(cards, (t) => t.seasonNumber, null);
  }

  Future<ReplayTitle?> season(String seasonId) async {
    final opened = await _open(drtvSeasonPath(seasonId));
    if (opened == null || opened.item['type'] != 'season') return null;
    final showJson = opened.show;
    final show = showJson == null ? null : _mapper.title(showJson);
    return _mapper.title(
      opened.item,
      context: show == null ? DrtvContext.none : _contextOf(show, showJson!),
      fallbackSeason: 1,
    );
  }

  Future<List<ReplayTitle>> episodes(String seasonId) async {
    final opened = await _open(drtvSeasonPath(seasonId));
    if (opened == null) return const [];
    final showJson = opened.show;
    final show = showJson == null ? null : _mapper.title(showJson);
    final base = show == null ? DrtvContext.none : _contextOf(show, showJson!);
    final context = DrtvContext(
      show: base.show,
      showTitle: base.showTitle,
      season: drtvSeasonRef(seasonId),
      seasonNumber: _seasonNumberOf(opened.item),
      access: drtvAccessOf(opened.item, inherited: base.access),
    );
    return _episodesOf(opened.item, context);
  }

  /// Episodes of a show that has no seasons of its own: whatever its page lists.
  Future<List<ReplayTitle>> allEpisodes(String showId) async {
    final opened = await _open(drtvShowPath(showId));
    final showJson = opened?.show;
    final show = showJson == null ? null : _mapper.title(showJson);
    if (opened == null || show == null || showJson == null) return const [];
    final base = _contextOf(show, showJson);
    final context = DrtvContext(
      show: base.show,
      showTitle: base.showTitle,
      season: drtvAllEpisodesRef(showId),
      seasonNumber: 1,
      access: base.access,
    );
    return _episodesOf(opened.item, context);
  }

  Future<ReplayTitle?> allSeason(String showId) async {
    final card = await show(showId);
    return card == null ? null : _syntheticSeason(card);
  }

  /// A show, season, episode or programme by its catalogue id.
  Future<ReplayTitle?> playable(String itemId) async {
    final item = await _api.item(itemId);
    return item == null ? null : _mapper.title(item);
  }

  Future<({DrtvJson item, DrtvJson? show})?> _open(String path) async {
    final item = (await _api.page(path, expand: true))?['item'];
    if (item is! DrtvJson) return null;
    final show = item['show'];
    return (item: item, show: show is DrtvJson ? show : (item['type'] == 'show' ? item : null));
  }

  DrtvContext _contextOf(ReplayTitle show, DrtvJson showJson) =>
      DrtvContext(show: show.ref, showTitle: show.title, access: drtvAccessOf(showJson));

  int? _seasonNumberOf(DrtvJson season) {
    final number = season['seasonNumber'];
    return number is num && number > 0 ? number.toInt() : null;
  }

  ReplayTitle _syntheticSeason(ReplayTitle show) => ReplayTitle(
    ref: drtvAllEpisodesRef(_showIdOf(show.ref)),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );

  String _showIdOf(ReplayRef show) => (parseDrtvId(show.nativeId) as DrtvShowId).showId;

  Future<List<ReplayTitle>> _episodesOf(DrtvJson season, DrtvContext context) async {
    final block = season['episodes'];
    if (block is! DrtvJson) return const [];
    final raw = <Object?>[...(block['items'] as List? ?? const [])];
    var next = _nextLink(block);
    for (var guard = 0; next != null && guard < _maxContinuations; guard++) {
      final more = await _api.next(next);
      raw.addAll(more?['items'] as List? ?? const []);
      next = more == null ? null : _nextLink(more);
    }
    return _ordered(_mapper.titles(raw, context: context), (t) => t.episodeNumber, (t) => t.airDate);
  }

  String? _nextLink(DrtvJson block) {
    final next = (block['paging'] as Map<String, dynamic>?)?['next'];
    return next is String && next.isNotEmpty ? next : null;
  }

  /// DR lists episodes newest first; the app wants them in watching order.
  List<ReplayTitle> _ordered(
    List<ReplayTitle> titles,
    int? Function(ReplayTitle) number,
    DateTime? Function(ReplayTitle)? date,
  ) {
    final indexed = titles.indexed.toList();
    indexed.sort((a, b) {
      final byNumber = _nullsLast(number(a.$2), number(b.$2));
      if (byNumber != 0) return byNumber;
      final dateA = date?.call(a.$2);
      final dateB = date?.call(b.$2);
      if (dateA != null && dateB != null && dateA != dateB) return dateA.compareTo(dateB);
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  int _nullsLast(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
