import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'zdfmediathek_api.dart';
import 'zdfmediathek_mapper.dart';
import 'zdfmediathek_numbering.dart';
import 'zdfmediathek_rails.dart';
import 'zdfmediathek_text.dart';

/// Native id of the season that stands for "every episode" of a show that has no season numbers.
const zdfAllEpisodesSeason = '_all';

/// A show with its seasons and their episodes, as far as ZDF lists them online.
class ZdfShowTree {
  final ReplayTitle show;
  final List<ReplayTitle> seasons;
  final Map<ReplayRef, List<ReplayTitle>> episodes;

  const ZdfShowTree({required this.show, required this.seasons, required this.episodes});

  ReplayTitle? episode(ReplayRef ref) {
    for (final list in episodes.values) {
      for (final episode in list) {
        if (episode.ref == ref) return episode;
      }
    }
    return null;
  }
}

/// Reads shows from their documents.
class ZdfCatalog {
  final ZdfApi _api;
  final ZdfMapper _mapper;

  ZdfCatalog(this._api, this._mapper);

  Future<ZdfShowTree?> tree(String showId) async => zdfBuildShowTree(await _api.document(showId), _mapper);
}

/// How the episodes of one show are numbered.
enum _Scheme {
  /// ZDF gives season numbers; videos without one go to season 0.
  numbered,

  /// Daily programmes that carry only a date in the title: the year is the season, the day of the year the episode.
  dated,

  /// Nothing to number by: one season holds everything.
  single,
}

typedef _Entry = ({Map<String, dynamic> teaser, String cluster, ZdfNumbers numbers});
typedef _Slot = ({int season, String id, int? episode});

/// Groups the videos of a brand or topic document into seasons.
///
/// Trailers, clips, sign-language copies and the videos of other shows (extras link to the documentary that made
/// them) are left out. Returns null when the document is not a show.
ZdfShowTree? zdfBuildShowTree(Map<String, dynamic> page, ZdfMapper mapper) {
  final document = page['document'];
  if (document is! Map<String, dynamic> || (document['type'] != 'brand' && document['type'] != 'topic')) return null;
  final show = mapper.showFromPage(page);
  if (show == null) return null;

  final entries = _entries(page, show.ref.nativeId, onlyOwnVideos: document['type'] == 'brand');
  final scheme = _schemeOf(entries);
  final groups = <int, List<ReplayTitle>>{};
  final ids = <int, String>{};
  for (final entry in entries) {
    final slot = _slotOf(scheme, entry);
    final seasonRef = zdfRef('${show.ref.nativeId}/${slot.id}');
    final context = ZdfContext(
      show: show.ref,
      showTitle: show.title,
      season: seasonRef,
      seasonNumber: slot.season,
      episodeNumber: slot.episode,
    );
    final episode = mapper.title(entry.teaser, context: context, clusterName: entry.cluster);
    if (episode == null) continue;
    ids[slot.season] = slot.id;
    groups.putIfAbsent(slot.season, () => []).add(episode);
  }

  final numbers = groups.keys.toList()..sort();
  final seasons = <ReplayTitle>[];
  final episodes = <ReplayRef, List<ReplayTitle>>{};
  for (final number in numbers) {
    final season = _season(show, scheme, number, ids[number]!, groups[number]!.length);
    seasons.add(season);
    episodes[season.ref] = groups[number]!..sort(_byEpisode);
  }
  return ZdfShowTree(show: show, seasons: seasons, episodes: episodes);
}

List<_Entry> _entries(Map<String, dynamic> page, String showId, {required bool onlyOwnVideos}) {
  final clusters = page['cluster'];
  if (clusters is! List) return const [];
  final seen = <String>{};
  final entries = <_Entry>[];
  for (final cluster in clusters.whereType<Map<String, dynamic>>()) {
    final name = zdfText(cluster['name']) ?? '';
    if (!zdfContentRows.contains(cluster['type']) || name.contains('Gebärdensprache')) continue;
    for (final teaser in (cluster['teaser'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      if (!_isEpisode(teaser) || (onlyOwnVideos && teaser['brandId'] != showId)) continue;
      if (!seen.add(teaser['id'] as String)) continue;
      entries.add((teaser: teaser, cluster: name, numbers: zdfNumbers(teaser, clusterName: name)));
    }
  }
  return entries;
}

bool _isEpisode(Map<String, dynamic> teaser) =>
    teaser['type'] == 'video' &&
    teaser['id'] is String &&
    teaser['contentType'] == 'episode' &&
    teaser['currentVideoType'] == 'episode' &&
    teaser['hasVideo'] != false;

_Scheme _schemeOf(List<_Entry> entries) {
  if (entries.any((e) => e.numbers.season != null)) return _Scheme.numbered;
  final allDated = entries.isNotEmpty && entries.every((e) => zdfNumbersFromTitleDate(e.teaser) != null);
  return allDated ? _Scheme.dated : _Scheme.single;
}

_Slot _slotOf(_Scheme scheme, _Entry entry) {
  switch (scheme) {
    case _Scheme.numbered:
      final season = entry.numbers.season ?? 0;
      return (season: season, id: '$season', episode: entry.numbers.episode);
    case _Scheme.dated:
      final dated = zdfNumbersFromTitleDate(entry.teaser)!;
      return (season: dated.season!, id: '${dated.season}', episode: dated.episode);
    case _Scheme.single:
      return (season: 1, id: zdfAllEpisodesSeason, episode: entry.numbers.episode);
  }
}

ReplayTitle _season(ReplayTitle show, _Scheme scheme, int number, String id, int count) => ReplayTitle(
  ref: zdfRef('${show.ref.nativeId}/$id'),
  kind: ReplayKind.season,
  title: _seasonTitle(show, scheme, number),
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: number,
  childCount: count,
  showRef: show.ref,
  showTitle: show.title,
);

String _seasonTitle(ReplayTitle show, _Scheme scheme, int number) => switch (scheme) {
  _Scheme.single => show.title,
  _Scheme.numbered when number == 0 => 'Weitere Folgen',
  _Scheme.numbered when number < 1900 => 'Staffel $number',
  _ => '$number',
};

/// Episode number first, then broadcast date, so two-part episodes that share a number stay in order.
int _byEpisode(ReplayTitle a, ReplayTitle b) {
  const last = 1 << 30;
  final byNumber = (a.episodeNumber ?? last).compareTo(b.episodeNumber ?? last);
  if (byNumber != 0) return byNumber;
  final byDate = (a.airDate ?? DateTime.utc(9999)).compareTo(b.airDate ?? DateTime.utc(9999));
  return byDate != 0 ? byDate : a.title.compareTo(b.title);
}
