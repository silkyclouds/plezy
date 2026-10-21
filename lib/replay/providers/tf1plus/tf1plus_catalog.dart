import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'tf1plus_api.dart';
import 'tf1plus_json.dart';
import 'tf1plus_mapper.dart';
import 'tf1plus_numbering.dart';
import 'tf1plus_refs.dart';

/// Pages of 100 videos read for one show before giving up; no show comes close, the bound only stops a loop.
const _maxPages = 30;
const _pageSize = 100;

/// A show with no replay left may still hold clips; they are listed in that order of preference.
const _videoTypes = ['REPLAY', 'EXTRACT', 'BONUS'];

/// Resolves the show -> season -> episode structure of TF1+ programmes.
///
/// A season ref is `programSlug/listId`. Programmes without season lists (news, magazines, one-off
/// shows) get one synthetic season, `programSlug/_all`, so every show has the same two levels.
/// A programme with a single replay is a film and has no children.
class Tf1Catalog {
  final Tf1Api _api;

  Tf1Catalog(this._api);

  /// The programme as a show or a film, or null when TF1+ no longer lists it.
  Future<ReplayTitle?> program(String slug) async => (await _load(slug))?.title;

  Future<List<ReplayTitle>> seasons(String slug) async {
    final loaded = await _load(slug);
    final show = loaded?.title;
    if (loaded == null || show == null || show.kind == ReplayKind.movie) return const [];

    final lists = tf1SeasonLists(loaded.detail);
    if (lists.isEmpty) return [_synthetic(show, tf1Replays(loaded.head).total)];

    final labels = [
      for (final list in lists) tf1Text(tf1Map(list['decoration'])['label']) ?? tf1Text(list['slug']) ?? '',
    ];
    final numbers = tf1SeasonNumbers(labels);
    final seasons = [
      for (var i = 0; i < lists.length; i++)
        if (tf1Text(lists[i]['id']) case final listId?) _season(show, listId, labels[i], numbers[i], lists[i]),
    ];
    return seasons..sort((a, b) => a.seasonNumber!.compareTo(b.seasonNumber!));
  }

  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final parts = tf1SplitSeasonId(seasonRef.nativeId);
    final season = (await seasons(parts.programSlug)).where((s) => s.ref == seasonRef).firstOrNull;
    if (season == null) return const [];
    final context = Tf1Context(
      show: season.showRef,
      showTitle: season.showTitle,
      season: season.ref,
      seasonNumber: season.seasonNumber,
    );
    return parts.listId == tf1AllEpisodesSeason
        ? _allVideos(parts.programSlug, context)
        : _listEpisodes(parts.programSlug, parts.listId, context, inOrder: !tf1IsYearLabel(season.title));
  }

  /// The video of a programme that has exactly one replay, and how many replays it has.
  Future<({String? videoId, int total})> singleReplay(String slug) async {
    final head = await _api.programVideos(slug, limit: 1);
    if (head == null) return (videoId: null, total: 0);
    final replays = tf1Replays(head);
    final first = replays.items.firstOrNull;
    return (videoId: replays.total == 1 && first != null ? tf1Text(first['id']) : null, total: replays.total);
  }

  Future<({Map<String, dynamic> head, Map<String, dynamic>? detail, ReplayTitle? title})?> _load(String slug) async {
    final head = await _api.programVideos(slug, limit: 1);
    if (head == null) return null;
    final id = tf1Text(head['id']);
    final detail = id == null ? null : await _api.programDetail(id);
    final video = tf1Replays(head).items.firstOrNull;
    return (head: head, detail: detail, title: tf1ProgramTitle(head, detail: detail, video: video));
  }

  /// Episodes of a season list. Seasons are read from the first episode on, but TF1+ sends some of them
  /// newest first, so [inOrder] sorts by episode number when every episode has one. Year archives keep
  /// the newest-first order of the site.
  Future<List<ReplayTitle>> _listEpisodes(
    String slug,
    String listId,
    Tf1Context context, {
    required bool inOrder,
  }) async {
    final titles = <ReplayTitle>[];
    for (var page = 0; page < _maxPages; page++) {
      final list = await _api.seasonEpisodes(slug, listId, page: page, limit: _pageSize);
      final items = list?['items'];
      if (items is! List || items.isEmpty) break;
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final video = tf1Map(item['video']);
        if (tf1VideoTitle(video, context: context, listImage: item['image']) case final title?) titles.add(title);
      }
      if (list?['hasNext'] != true) break;
    }
    final unique = _withoutRepeats(titles);
    if (inOrder && unique.every((t) => t.episodeNumber != null)) {
      unique.sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
    }
    return unique;
  }

  Future<List<ReplayTitle>> _allVideos(String slug, Tf1Context context) async {
    for (final type in _videoTypes) {
      final titles = await _videosOfType(slug, type, context);
      if (titles.isNotEmpty) return titles;
    }
    return const [];
  }

  Future<List<ReplayTitle>> _videosOfType(String slug, String type, Tf1Context context) async {
    final titles = <ReplayTitle>[];
    for (var page = 0; page < _maxPages; page++) {
      final head = await _api.programVideos(slug, page: page, limit: _pageSize, type: type);
      final replays = tf1Replays(head);
      for (final video in replays.items) {
        if (tf1VideoTitle(video, context: context) case final title?) titles.add(title);
      }
      if (replays.items.isEmpty || titles.length >= replays.total) break;
    }
    return _withoutRepeats(titles);
  }

  List<ReplayTitle> _withoutRepeats(List<ReplayTitle> titles) {
    final seen = <ReplayRef>{};
    return [
      for (final title in titles)
        if (seen.add(title.ref)) title,
    ];
  }

  ReplayTitle _season(ReplayTitle show, String listId, String label, int number, Map<String, dynamic> list) =>
      ReplayTitle(
        ref: tf1SeasonRef(show.ref.nativeId, listId),
        kind: ReplayKind.season,
        title: label.isEmpty ? 'Saison $number' : label,
        posterUrl: show.posterUrl,
        backdropUrl: show.backdropUrl,
        seasonNumber: number,
        childCount: (list['total'] as num?)?.toInt(),
        showRef: show.ref,
        showTitle: show.title,
        availability: show.availability,
      );

  ReplayTitle _synthetic(ReplayTitle show, int total) => ReplayTitle(
    ref: tf1SeasonRef(show.ref.nativeId, tf1AllEpisodesSeason),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    childCount: total > 0 ? total : null,
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );
}

/// The replays page of a programme record: its video list and the total the programme holds.
({List<Map<String, dynamic>> items, int total}) tf1Replays(Map<String, dynamic>? programme) {
  final videos = tf1Map(programme?['videos']);
  final items = videos['items'];
  return (
    items: items is List ? items.whereType<Map<String, dynamic>>().toList() : const [],
    total: (videos['total'] as num?)?.toInt() ?? (tf1Map(programme?['replay'])['total'] as num?)?.toInt() ?? 0,
  );
}
