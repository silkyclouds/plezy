import '../../model/replay_title.dart';
import 'aljazeera_api.dart';
import 'aljazeera_categories.dart';
import 'aljazeera_mapper.dart';
import 'aljazeera_text.dart';

/// Posts read per request when a whole year is listed.
const _pageSize = 50;

/// Programmes per request. The site accepts up to 100; the longest section has about a hundred.
const _programmePage = 60;
const _maxProgrammePages = 6;

/// Upper bound on the pages read for one season, so a year of daily clips cannot run away.
const _maxSeasonPages = 12;

/// Programmes are probed no deeper than this many posts.
const _probeLimit = 1 << 14;

const _spanTtl = Duration(minutes: 10);

/// The years a programme has posts in, and how many posts it has.
class _Span {
  final int newestYear;
  final int oldestYear;
  final int count;

  const _Span(this.newestYear, this.oldestYear, this.count);
}

/// Resolves the show -> season -> episode structure of Al Jazeera programmes.
///
/// The site lists a programme's episodes newest first by offset, with no total and no seasons. A season is a
/// calendar year. The years are found by probing single posts (doubling the offset, then halving), a whole
/// year is read from the offset where it starts, and an episode's number is its place in that year by date.
class AljazeeraCatalog {
  final AljazeeraApi _api;
  final DateTime Function() _clock;
  final Map<String, ({DateTime at, _Span? span})> _spans = {};

  AljazeeraCatalog(this._api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The programmes of one section, as shows.
  Future<List<ReplayTitle>> programmes(String category) async {
    final shows = <ReplayTitle>[];
    for (var page = 0; page < _maxProgrammePages; page++) {
      final batch = await _api.programmes(category, offset: page * _programmePage, quantity: _programmePage);
      shows.addAll(batch.map(aljazeeraShow).whereType<ReplayTitle>());
      if (batch.length < _programmePage) break;
    }
    return shows;
  }

  /// Every programme of both sections. A programme listed in both appears once.
  Future<List<ReplayTitle>> allProgrammes() async {
    final byRef = <Object, ReplayTitle>{};
    for (final category in const [aljazeeraShowsCategory, aljazeeraDocumentariesCategory]) {
      for (final show in await programmes(category)) {
        if (show.ref.nativeId == aljazeeraClipsBrowseId) continue;
        byRef.putIfAbsent(show.ref, () => show);
      }
    }
    return byRef.values.toList();
  }

  Future<ReplayTitle?> show(String slug) async {
    final all = await allProgrammes();
    return all.where((s) => s.ref.nativeId == slug).firstOrNull;
  }

  /// One season per year between the newest and the oldest post, oldest first.
  Future<List<ReplayTitle>> seasons(String slug) async {
    final parent = await show(slug);
    final span = parent == null ? null : await _span(slug);
    if (parent == null || span == null) return const [];
    return [for (var year = span.oldestYear; year <= span.newestYear; year++) aljazeeraSeason(parent, year)];
  }

  /// The playable episodes of one year in broadcast order, oldest first.
  ///
  /// Numbers are given only when the whole year was read.
  Future<List<ReplayTitle>> episodes(String slug, int year) async {
    final parent = await show(slug);
    final span = parent == null ? null : await _span(slug);
    if (parent == null || span == null || year < span.oldestYear || year > span.newestYear) return const [];

    final start = await _firstOffsetUpTo(slug, year, span.count);
    final (:posts, :complete) = await _readYear(slug, year, start);
    final playable = [
      for (final post in posts)
        if (aljazeeraVideoId(post) != null) post,
    ]..sort(_byDate);
    final seen = <Object>{};
    final titles = <ReplayTitle>[];
    for (final post in playable) {
      final title = aljazeeraEpisode(
        post,
        programme: slug,
        showTitle: parent.title,
        number: complete ? titles.length + 1 : null,
      );
      if (title != null && seen.add(title.ref)) titles.add(title);
    }
    return titles;
  }

  /// A page of a programme's playable episodes, newest first, and whether the page was full.
  Future<({List<ReplayTitle> titles, bool more})> latest(String slug, {int offset = 0, int quantity = 20}) async {
    final posts = await _api.posts(slug, offset: offset, quantity: quantity);
    return (titles: aljazeeraEpisodes(posts, programme: slug), more: posts.length >= quantity);
  }

  /// A page of the newsfeed, newest first, and whether the page was full.
  Future<({List<ReplayTitle> titles, bool more})> clips({int offset = 0, int quantity = 20}) async {
    final posts = await _api.posts(aljazeeraClipsBrowseId, offset: offset, quantity: quantity);
    return (titles: aljazeeraClips(posts), more: posts.length >= quantity);
  }

  Future<_Span?> _span(String slug) async {
    final hit = _spans[slug];
    if (hit != null && _clock().difference(hit.at) < _spanTtl) return hit.span;
    final span = await _measure(slug);
    _spans[slug] = (at: _clock(), span: span);
    return span;
  }

  /// Finds the end of the list by doubling the offset until a probe is empty, then halving the gap.
  Future<_Span?> _measure(String slug) async {
    final newest = await _postAt(slug, 0);
    if (newest == null) return null;
    var present = 0;
    var oldest = newest;
    var absent = 1;
    while (absent < _probeLimit) {
      final post = await _postAt(slug, absent);
      if (post == null) break;
      present = absent;
      oldest = post;
      absent *= 2;
    }
    while (absent - present > 1) {
      final middle = (present + absent) ~/ 2;
      final post = await _postAt(slug, middle);
      if (post == null) {
        absent = middle;
      } else {
        present = middle;
        oldest = post;
      }
    }
    final newestYear = _yearOf(newest);
    final oldestYear = _yearOf(oldest);
    return newestYear == null || oldestYear == null ? null : _Span(newestYear, oldestYear, absent);
  }

  /// The smallest offset whose post is from [year] or earlier, which is where the year starts in a newest-first list.
  Future<int> _firstOffsetUpTo(String slug, int year, int count) async {
    if (await _startsBy(slug, 0, year)) return 0;
    var before = 0;
    var upTo = count;
    while (upTo - before > 1) {
      final middle = (before + upTo) ~/ 2;
      if (await _startsBy(slug, middle, year)) {
        upTo = middle;
      } else {
        before = middle;
      }
    }
    return upTo;
  }

  Future<bool> _startsBy(String slug, int offset, int year) async {
    final post = await _postAt(slug, offset);
    final posted = post == null ? null : _yearOf(post);
    return posted == null || posted <= year;
  }

  Future<({List<Map<String, dynamic>> posts, bool complete})> _readYear(String slug, int year, int start) async {
    final posts = <Map<String, dynamic>>[];
    var offset = start;
    for (var page = 0; page < _maxSeasonPages; page++) {
      final batch = await _api.posts(slug, offset: offset, quantity: _pageSize);
      for (final post in batch) {
        final posted = _yearOf(post);
        if (posted != null && posted < year) return (posts: posts, complete: true);
        if (posted == year) posts.add(post);
      }
      if (batch.length < _pageSize) return (posts: posts, complete: true);
      offset += _pageSize;
    }
    return (posts: posts, complete: false);
  }

  Future<Map<String, dynamic>?> _postAt(String slug, int offset) async =>
      (await _api.posts(slug, offset: offset, quantity: 1)).firstOrNull;

  int? _yearOf(Map<String, dynamic> post) => aljazeeraDate(post['date'])?.year;

  int _byDate(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byDate = (aljazeeraDate(a['date']) ?? DateTime(0)).compareTo(aljazeeraDate(b['date']) ?? DateTime(0));
    return byDate != 0 ? byDate : '${a['id']}'.compareTo('${b['id']}');
  }
}
