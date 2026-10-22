import '../../model/replay_title.dart';
import 'france24_api.dart';
import 'france24_language.dart';
import 'france24_mapper.dart';
import 'france24_models.dart';
import 'france24_numbering.dart';

/// Programmes with at most this many pages of editions are read in full to find their years; larger
/// ones are bounded by their first and last page.
const _fullScanPages = 3;

/// Programmes per page of the broadcaster's list.
const france24ProgrammePageSize = 24;

/// Upper bound on the pages read from the short programme list.
const _maxListPages = 10;

/// Upper bound on the pages read for one season, so a changed server cannot make a loop run away.
const _maxSeasonPages = 40;

/// Resolves the show -> season -> episode structure of France 24 programmes.
///
/// The broadcaster lists a programme's editions newest first and numbers nothing, so a season is a
/// calendar year and the pages that hold a given day are found by bisecting on the edition dates.
class France24Catalog {
  final France24Api _api;
  final DateTime Function() _clock;

  France24Catalog(this._api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  France24Language get _language => _api.language;

  String get _source => _language.sourceId;

  Future<ReplayTitle?> show(String programmeNid) async {
    if (_language.hiddenProgrammes.contains(programmeNid)) return null;
    final page = await _api.programmes(nid: programmeNid);
    final programme = page.items.where((p) => p.nid == programmeNid).firstOrNull;
    return programme == null ? null : france24Show(_source, programme);
  }

  /// Every programme worth listing, alphabetically. The list holds a few dozen entries over a couple of pages.
  Future<List<France24Programme>> allProgrammes() async {
    final first = await _api.programmes();
    final programmes = [...first.items];
    for (var page = 2; page <= first.lastPage && page <= _maxListPages; page++) {
      programmes.addAll((await _api.programmes(page: page)).items);
    }
    return [
      for (final programme in programmes)
        if (!_language.hiddenProgrammes.contains(programme.nid)) programme,
    ];
  }

  /// One page of the programme list, numbered from 1.
  ///
  /// When programmes are hidden the pages are cut from the filtered list, so every page but the last stays
  /// full and a client that derives the next offset from the item count never repeats a page.
  Future<France24Page<France24Programme>> programmePage(int page) async {
    if (_language.hiddenProgrammes.isEmpty) return _api.programmes(page: page);
    final all = await allProgrammes();
    final from = (page - 1) * france24ProgrammePageSize;
    final items = from >= all.length ? <France24Programme>[] : all.skip(from).take(france24ProgrammePageSize).toList();
    return France24Page(
      items: items,
      total: all.length,
      page: page,
      lastPage: all.isEmpty ? 1 : (all.length / france24ProgrammePageSize).ceil(),
    );
  }

  /// One season per year that has an edition with a video, oldest first.
  Future<List<ReplayTitle>> seasons(String programmeNid) async {
    final parent = await show(programmeNid);
    if (parent == null) return const [];
    final years = await _years(programmeNid);
    return [for (final year in years) france24Season(_source, parent, year)];
  }

  /// The editions of one year in broadcast order, oldest first.
  Future<List<ReplayTitle>> episodes(String programmeNid, int year) async {
    final first = await _firstPageEndingBy(programmeNid, france24EndOfYear(year));
    if (first == null) return const [];
    final editions = <France24Edition>[];
    final last = first.page + _maxSeasonPages - 1;
    for (var page = first.page; page <= first.lastPage && page <= last; page++) {
      final items = page == first.page ? first.items : (await _api.editions(programmeNid, page: page)).items;
      editions.addAll(items.where((e) => e.day?.year == year));
      if (items.any((e) => (e.day?.year ?? year) < year)) break;
    }
    final episodes = france24Episodes(_source, editions, _clock());
    return _inBroadcastOrder(episodes);
  }

  /// One edition by edition token, found without knowing which page holds it.
  Future<France24Edition?> edition(String programmeNid, String editionToken) async {
    final (nid: editionNid, :day) = france24ParseEditionToken(editionToken);
    if (day == null) return null;
    final start = await _firstPageEndingBy(programmeNid, france24EndOfDay(day));
    if (start == null) return null;
    for (var page = start.page; page <= start.lastPage && page < start.page + 3; page++) {
      final items = page == start.page ? start.items : (await _api.editions(programmeNid, page: page)).items;
      final hit = items.where((e) => e.nid == editionNid).firstOrNull;
      if (hit != null) return hit;
      if (_oldestDay(items).isBefore(day)) return null;
    }
    return null;
  }

  Future<ReplayTitle?> clip(String videoNid) async {
    final video = await clipVideo(videoNid);
    return video == null ? null : france24Clip(_source, video, _clock());
  }

  Future<France24Video?> clipVideo(String videoNid) async {
    final page = await _api.videos(nid: videoNid);
    return page.items.where((v) => v.nid == videoNid).firstOrNull;
  }

  Future<List<int>> _years(String programmeNid) async {
    final first = await _api.editions(programmeNid);
    final read = first.lastPage <= _fullScanPages ? [for (var p = 2; p <= first.lastPage; p++) p] : [first.lastPage];
    final pages = [first.items];
    if (first.lastPage > 1) {
      for (final page in read) {
        pages.add((await _api.editions(programmeNid, page: page)).items);
      }
    }
    final years = {for (final items in pages) ..._yearsOf(items)};
    if (first.lastPage > _fullScanPages && years.isNotEmpty) {
      final oldest = years.reduce((a, b) => a < b ? a : b);
      final newest = years.reduce((a, b) => a > b ? a : b);
      years.addAll([for (var year = oldest; year <= newest; year++) year]);
    }
    return years.toList()..sort();
  }

  Iterable<int> _yearsOf(List<France24Edition> editions) => [
    for (final e in editions)
      if (e.video != null && e.video!.formats.isNotEmpty && e.day != null) e.day!.year,
  ];

  /// The first page whose oldest edition is not later than [cutoff], found by bisection.
  ///
  /// Every page before it holds only editions after [cutoff]. Null when the whole programme is later.
  Future<_Located?> _firstPageEndingBy(String programmeNid, DateTime cutoff) async {
    final first = await _api.editions(programmeNid);
    if (first.items.isEmpty) return null;
    if (!_oldestDay(first.items).isAfter(cutoff)) return _Located(1, first.lastPage, first.items);
    if (first.lastPage == 1) return null;

    final lastPage = await _api.editions(programmeNid, page: first.lastPage);
    if (_oldestDay(lastPage.items).isAfter(cutoff)) return null;

    var late = 1;
    var early = first.lastPage;
    var earlyItems = lastPage.items;
    while (early - late > 1) {
      final middle = (late + early) ~/ 2;
      final items = (await _api.editions(programmeNid, page: middle)).items;
      if (_oldestDay(items).isAfter(cutoff)) {
        late = middle;
      } else {
        early = middle;
        earlyItems = items;
      }
    }
    return _Located(early, first.lastPage, earlyItems);
  }

  DateTime _oldestDay(List<France24Edition> editions) {
    DateTime? oldest;
    for (final day in editions.map((e) => e.day)) {
      if (day != null && (oldest == null || day.isBefore(oldest))) oldest = day;
    }
    return oldest ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  List<ReplayTitle> _inBroadcastOrder(List<ReplayTitle> episodes) {
    final unique = {for (final e in episodes) e.ref: e}.values.toList();
    unique.sort((a, b) {
      final byDate = (a.airDate ?? DateTime(0)).compareTo(b.airDate ?? DateTime(0));
      return byDate != 0 ? byDate : a.ref.nativeId.compareTo(b.ref.nativeId);
    });
    return unique;
  }
}

class _Located {
  final int page;
  final int lastPage;
  final List<France24Edition> items;

  const _Located(this.page, this.lastPage, this.items);
}
