import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'm6plus_api.dart';
import 'm6plus_geo.dart';
import 'm6plus_mapper.dart';

/// A video as the API sent it, next to the title it maps to.
typedef _Entry = ({Map<String, dynamic> raw, ReplayTitle title});

/// Shows, seasons and episodes of one programme.
///
/// The catalogue has no season objects. Seasons are read off the videos: full videos group by their season
/// number, extracts and podcasts each get a season of their own, and videos without a season number share one.
class M6plusShows {
  static const _maxFullPages = 30;
  static const _maxExtraPages = 3;

  final M6plusApi _api;
  final M6plusGeo _geo;
  final DateTime Function() _clock;

  M6plusShows(this._api, this._geo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  Future<ReplayTitle?> show(String programId) async {
    final program = await _api.program(programId);
    return program == null ? null : m6plusTitleFromProgram(program);
  }

  /// One title by video id, or null when it was withdrawn.
  Future<ReplayTitle?> video(String clipId) async {
    final raw = await _api.video(clipId);
    return raw == null ? null : m6plusTitleFromVideo(raw, country: _geo.country, now: _clock());
  }

  Future<List<ReplayTitle>> seasons(String programId) async {
    final program = await _api.program(programId);
    if (program == null) return const [];
    final show = m6plusTitleFromProgram(program);
    if (show.kind == ReplayKind.movie) return const [];

    final entries = <_Entry>[
      ...await _entries(program, 'vi'),
      ...await _entries(program, 'vc'),
      ...await _entries(program, 'podcast'),
    ];
    final groups = <String, List<_Entry>>{};
    for (final entry in entries) {
      final key = _keyOf(entry.title);
      if (key != null) groups.putIfAbsent(key, () => []).add(entry);
    }
    final keys = groups.keys.toList()..sort(_compareKeys);
    final onlyOne = keys.length == 1;
    return [for (final key in keys) _season(programId, key, groups[key]!, show, onlyOne)];
  }

  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final parts = season.nativeId.split('/');
    if (parts.length != 2) return const [];
    final program = await _api.program(parts[0]);
    if (program == null) return const [];
    final key = parts[1];
    final type = switch (key) {
      m6plusExtractsSeason => 'vc',
      m6plusPodcastsSeason => 'podcast',
      _ => 'vi',
    };
    final entries = [
      for (final e in await _entries(program, type))
        if (_keyOf(e.title) == key) e,
    ];
    return [for (final e in _ordered(entries, type)) e.title];
  }

  Future<List<_Entry>> _entries(Map<String, dynamic> program, String type) async {
    final expected = m6plusInt((program['count'] as Map?)?[type]) ?? 0;
    if (expected == 0) return const [];
    final id = '${program['id']}';
    final maxPages = type == 'vi' ? _maxFullPages : _maxExtraPages;
    final seen = <String>{};
    final entries = <_Entry>[];
    var fetched = 0;
    for (var page = 0; page < maxPages; page++) {
      final batch = await _api.videos(id, type: type, offset: page * M6plusApi.pageSize, sort: _sort(type));
      fetched += batch.length;
      for (final raw in batch) {
        final title = m6plusTitleFromVideo(raw, country: _geo.country, now: _clock());
        if (title != null && raw['type'] == type && seen.add(title.ref.nativeId)) entries.add((raw: raw, title: title));
      }
      if (batch.length < M6plusApi.pageSize || fetched >= expected) break;
    }
    return entries;
  }

  String _sort(String type) => type == 'vi' ? 'episode_asc' : 'asset_publication_desc';

  String? _keyOf(ReplayTitle title) => title.seasonRef?.nativeId.split('/').last;

  /// Numbered seasons first, then unnumbered episodes, extracts and podcasts.
  int _compareKeys(String a, String b) => _order(a).compareTo(_order(b));

  num _order(String key) => switch (key) {
    m6plusOtherSeason => 1e6,
    m6plusExtractsSeason => 2e6,
    m6plusPodcastsSeason => 3e6,
    _ => int.tryParse(key.substring(1)) ?? 4e6,
  };

  ReplayTitle _season(String programId, String key, List<_Entry> entries, ReplayTitle show, bool onlyOne) {
    final first = entries.first;
    final number = switch (key) {
      m6plusExtractsSeason => 0,
      m6plusPodcastsSeason => null,
      m6plusOtherSeason => onlyOne ? 1 : null,
      _ => first.title.seasonNumber,
    };
    final playable = entries.where((e) => e.title.availability == ReplayAvailability.playable);
    return ReplayTitle(
      ref: m6plusRef('$programId/$key'),
      kind: ReplayKind.season,
      title: _seasonName(key, first.raw, number),
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: number,
      childCount: entries.length,
      showRef: show.ref,
      showTitle: show.title,
      availability: playable.isNotEmpty ? ReplayAvailability.playable : first.title.availability,
    );
  }

  String _seasonName(String key, Map<String, dynamic> raw, int? number) {
    if (key == m6plusExtractsSeason) return 'Extraits et bonus';
    if (key == m6plusPodcastsSeason) return 'Podcasts';
    if (key == m6plusOtherSeason) return 'Épisodes';
    final product = ((raw['clips'] as List?)?.firstOrNull as Map?)?['product'] as Map?;
    final named = (product?['season_title'] as String?)?.trim();
    // A season numbered like a year ("2024") reads better under its own name.
    return number != null && number >= 1000 && named != null && named.isNotEmpty ? named : 'Saison $number';
  }

  /// Full videos by episode, then part; extracts and podcasts stay newest first as the API sends them.
  List<_Entry> _ordered(List<_Entry> entries, String type) {
    if (type != 'vi') return entries;
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
    int part(_Entry e) =>
        m6plusInt((((e.raw['clips'] as List?)?.firstOrNull as Map?)?['product'] as Map?)?['part_number']) ?? 0;
    indexed.sort((a, b) {
      final byEpisode = (a.$2.title.episodeNumber ?? 1 << 30).compareTo(b.$2.title.episodeNumber ?? 1 << 30);
      if (byEpisode != 0) return byEpisode;
      final byPart = part(a.$2).compareTo(part(b.$2));
      return byPart != 0 ? byPart : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }
}
