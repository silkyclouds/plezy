import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'stvr_api.dart';
import 'stvr_mapper.dart';
import 'stvr_numbering.dart';
import 'stvr_record.dart';
import 'stvr_refs.dart';

const _pageSize = 100;
const _maxPages = 10;

/// Resolves the show -> season -> episode structure of the archive.
///
/// The broadcaster has no seasons. A series is a flat run of dated recordings, and each series of a programme is a
/// show of its own whose name ends in a Roman numeral. A show is therefore a series id, its seasons are the series
/// that share its base name, and a show with no numbered siblings gets one synthetic season.
class StvrCatalog {
  final StvrApi _api;
  final DateTime Function() _now;

  StvrCatalog(this._api, {DateTime Function()? now}) : _now = now ?? (() => DateTime.now().toUtc());

  /// The show behind a series id, or null when the archive holds nothing under it.
  Future<ReplayTitle?> show(ReplayRef ref) async {
    final first = await _firstRecord(ref.nativeId);
    return first == null ? null : stvrShowFromRecord(first.record, ref: ref);
  }

  Future<List<ReplayTitle>> seasons(ReplayRef showRef) async {
    final first = await _firstRecord(showRef.nativeId);
    if (first == null) return const [];
    final show = stvrShowFromRecord(first.record, ref: showRef);
    final siblings = await _siblingSeries(first.record, showRef.nativeId);
    final numbered = _numberSeasons(siblings);
    final named = numbered.length > 1 || first.record.showName.season != null;
    return [
      for (final entry in numbered)
        ReplayTitle(
          ref: stvrSeasonRef(showRef.nativeId, entry.record.series),
          kind: ReplayKind.season,
          title: named ? 'Séria ${entry.number}' : show.title,
          posterUrl: entry.record.image ?? show.posterUrl,
          backdropUrl: entry.record.image ?? show.backdropUrl,
          seasonNumber: entry.number,
          childCount: entry.record.series == first.record.series ? first.total : null,
          showRef: showRef,
          showTitle: show.title,
        ),
    ];
  }

  /// The recordings of one season, oldest first and numbered.
  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final ids = stvrParseSeasonId(seasonRef.nativeId);
    if (ids == null) return const [];
    final listing = await _allRecords(ids.season);
    if (listing.records.isEmpty) return const [];

    final oldestFirst = listing.records.reversed.toList();
    final numbers = stvrEpisodeNumbers([for (final r in oldestFirst) r.subtitle], total: listing.total);
    final showRef = stvrShowRef(ids.show);
    final now = _now();
    return [
      for (var i = 0; i < oldestFirst.length; i++)
        stvrEpisodeFromRecord(
          oldestFirst[i],
          show: showRef,
          season: seasonRef,
          seasonNumber: oldestFirst[i].showName.season,
          episodeNumber: numbers[i],
          now: now,
        ),
    ];
  }

  /// One recording by its episode id, found through the list of its air day.
  Future<ReplayTitle?> episode(ReplayRef ref) async {
    final id = stvrParseEpisodeId(ref.nativeId);
    if (id == null) return null;
    for (var page = 1; page <= 3; page++) {
      final data = await _api.archive(page: page, size: _pageSize, date: id.airDay);
      final records = StvrRecord.fromPage(data);
      final hit = records.where((r) => r.id == id.programId).firstOrNull;
      if (hit != null) return stvrEpisodeFromRecord(hit, now: _now());
      if (records.length < _pageSize) break;
    }
    return null;
  }

  Future<({StvrRecord record, int total})?> _firstRecord(String seriesId) async {
    final data = await _api.archive(series: seriesId, size: 1);
    final record = StvrRecord.fromPage(data).firstOrNull;
    return record == null ? null : (record: record, total: StvrRecord.totalOf(data));
  }

  /// The first recording of every series sharing the show's base name, the show's own series included.
  Future<List<StvrRecord>> _siblingSeries(StvrRecord own, String showId) async {
    final name = own.showName;
    if (name.season == null) return [own];
    final found = StvrRecord.fromPage(await _api.archive(size: _pageSize, query: name.base));
    final bySeries = <int, StvrRecord>{own.series: own};
    for (final record in found) {
      if (record.showName.key == name.key) bySeries.putIfAbsent(record.series, () => record);
    }
    return bySeries.values.toList();
  }

  /// Series ordered by their numeral. When two series claim one number, or one has none among numbered ones, the
  /// order of the series ids decides and numbers are handed out from 1.
  List<({StvrRecord record, int number})> _numberSeasons(List<StvrRecord> series) {
    final ordered = [...series]
      ..sort((a, b) {
        final byNumber = (a.showName.season ?? 1).compareTo(b.showName.season ?? 1);
        return byNumber != 0 ? byNumber : a.series.compareTo(b.series);
      });
    final stated = [for (final r in ordered) r.showName.season ?? 1];
    final distinct = stated.toSet().length == stated.length;
    return [for (var i = 0; i < ordered.length; i++) (record: ordered[i], number: distinct ? stated[i] : i + 1)];
  }

  /// Every recording of a series, newest first, up to a bound that keeps daily news from costing hundreds of calls.
  Future<({List<StvrRecord> records, int total})> _allRecords(String seriesId) async {
    final records = <StvrRecord>[];
    var total = 0;
    for (var page = 1; page <= _maxPages; page++) {
      final data = await _api.archive(page: page, size: _pageSize, series: seriesId);
      final batch = StvrRecord.fromPage(data);
      total = StvrRecord.totalOf(data);
      records.addAll(batch);
      if (batch.length < _pageSize || records.length >= total) break;
    }
    return (records: records, total: total < records.length ? records.length : total);
  }
}
