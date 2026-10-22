import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtbf_bff.dart';
import 'rtbf_mapper.dart';
import 'rtbf_numbering.dart';
import 'rtbf_rights.dart';
import 'rtbf_tabs.dart';

const _pageSize = '50';
const _maxPages = 20;

/// Season keys that start with this letter are numbers read from episode titles, not tabs of the page.
const _derivedKey = 'n';

/// Resolves the show, season and episode levels of Auvio.
///
/// A programme page lists its episodes as tabs; each tab becomes a season. A show whose single tab is
/// "all episodes" gets one season, so every show has the same two levels.
class RtbfCatalog {
  final RtbfBff _bff;
  final RtbfMapper _mapper;
  final RtbfRights _rights;

  RtbfCatalog(this._bff, this._mapper, this._rights);

  /// A programme as a show, or as a movie when it holds a single film. Null when Auvio no longer has it.
  Future<ReplayTitle?> show(String programId) async {
    final content = _content(await _page(programId));
    if (content == null) return null;
    final mediaId = _standaloneMediaId(content);
    final rights = mediaId == null ? const <String, ReplayAvailability>{} : await _rights.predict([mediaId]);
    return _mapper.programPage(content, rights: rights);
  }

  /// The media id of the film inside a one-off programme, or null for a programme with episodes.
  Future<String?> standaloneMediaId(String programId) async {
    final content = _content(await _page(programId));
    return content == null ? null : _standaloneMediaId(content);
  }

  /// One video or audio item with its programme, cast and rights.
  Future<ReplayTitle?> media(String mediaId) async {
    final page = await _bff.find('pages/media/$mediaId');
    final content = _content(page);
    if (content == null) return null;
    return _mapper.mediaPage(content, rights: await _rights.predict([mediaId]), image: _pageImage(page));
  }

  /// The picture of the page's own video: a media page carries it in its SEO block rather than in the content.
  String? _pageImage(Map<String, dynamic>? page) {
    final seo = (page?['meta'] as Map?)?['seo'];
    final image = seo is Map ? seo['image'] : null;
    final url = image is Map ? image['url'] : null;
    return url is String && url.isNotEmpty ? url : null;
  }

  Future<List<ReplayTitle>> seasons(String programId) async {
    final page = await _page(programId);
    final content = _content(page);
    final show = content == null ? null : _mapper.programPage(content);
    if (page == null || show == null || show.kind != ReplayKind.show) return const [];
    final tabs = await _tabs(page);
    if (tabs.length == 1 && !tabs.single.key.startsWith('s')) return _singleTabSeasons(programId, show, tabs.single);
    return [
      for (var i = 0; i < tabs.length; i++)
        _season(show, rtbfSeasonRef(programId, tabs[i].key), tabs[i].title, tabs[i].number ?? i + 1, tabs[i].count),
    ];
  }

  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final parts = season.nativeId.split('/');
    final programId = parts.first.substring(1);
    final key = parts.length > 1 ? parts[1] : 'all';

    final page = await _page(programId);
    final content = _content(page);
    final show = content == null ? null : _mapper.programPage(content);
    if (page == null || show == null) return const [];
    final tabs = await _tabs(page);

    final derived = key.startsWith(_derivedKey) ? int.tryParse(key.substring(_derivedKey.length)) : null;
    final tab = derived == null ? _tabForKey(tabs, key) : tabs.singleOrNull;
    if (tab == null) return const [];
    final number = derived ?? (key == 'all' ? null : tab.number);

    final all = await _allCards(tab.contentPath);
    final cards = derived == null ? all : all.where((c) => _derivedSeason(c) == derived).toList();
    final rights = await _rights.predict([
      for (final card in cards)
        if (card is Map<String, dynamic> && card['type'] == 'VIDEO' && card['id'] != null) card['id'].toString(),
    ]);
    final context = RtbfContext(
      show: show.ref,
      showTitle: show.title,
      season: season,
      seasonNumber: number,
      episodes: true,
    );
    return _mapper.cards(cards, context: context, rights: rights);
  }

  /// A show whose episodes sit in one tab says its seasons only in the episode titles (`Sxx`). The first
  /// page tells whether any title carries one; only then is the whole tab read and split by season.
  /// Otherwise the tab is the one season, whatever year it was filed under.
  Future<List<ReplayTitle>> _singleTabSeasons(String programId, ReplayTitle show, RtbfTab tab) async {
    final first = (await _bff.find(tab.contentPath, query: const {'_limit': _pageSize}))?['data'];
    final firstCards = first is Map && first['content'] is List ? first['content'] as List : const [];
    if (!firstCards.any((c) => _numberingOf(c).season != null)) {
      final numbered = firstCards.any((c) => _numberingOf(c).isNumbered);
      final key = numbered ? '${_derivedKey}1' : 'all';
      return [_season(show, rtbfSeasonRef(programId, key), numbered ? '' : tab.title, 1, tab.count)];
    }

    final counts = <int, int>{};
    for (final card in await _allCards(tab.contentPath)) {
      counts.update(_derivedSeason(card), (n) => n + 1, ifAbsent: () => 1);
    }
    final numbers = counts.keys.toList()..sort();
    return [for (final n in numbers) _season(show, rtbfSeasonRef(programId, '$_derivedKey$n'), '', n, counts[n])];
  }

  /// The single tab of a show stands for the season keyed `all`, whatever year context it was filed under.
  RtbfTab? _tabForKey(List<RtbfTab> tabs, String key) {
    final exact = tabs.where((t) => t.key == key).firstOrNull;
    return exact ?? (key == 'all' ? tabs.singleOrNull : null);
  }

  RtbfNumbering _numberingOf(Object? card) => card is Map<String, dynamic>
      ? rtbfParseNumbering(title: card['title'] as String?, subtitle: card['subtitle'] as String?)
      : const RtbfNumbering(showTitle: '', episodeTitle: '');

  int _derivedSeason(Object? card) => _numberingOf(card).season ?? 1;

  ReplayTitle _season(ReplayTitle show, ReplayRef ref, String title, int number, int? count) => ReplayTitle(
    ref: ref,
    kind: ReplayKind.season,
    title: title.isEmpty ? 'Saison $number' : title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: number,
    childCount: count,
    showRef: show.ref,
    showTitle: show.title,
  );

  Future<Map<String, dynamic>?> _page(String programId) => _bff.find('pages/emission/$programId');

  Map<String, dynamic>? _content(Map<String, dynamic>? page) {
    final content = (page?['data'] as Map?)?['content'];
    return content is Map<String, dynamic> ? content : null;
  }

  String? _standaloneMediaId(Map<String, dynamic> content) {
    final media = content['media'];
    if (content['type'] != 'STANDALONE' || media is! Map || media['id'] == null) return null;
    return media['id'].toString();
  }

  Future<List<RtbfTab>> _tabs(Map<String, dynamic> page) async {
    final widgets = (page['data'] as Map?)?['widgets'];
    if (widgets is! List) return const [];
    final tabList = widgets.whereType<Map<String, dynamic>>().where((w) => w['type'] == 'TAB_LIST').firstOrNull;
    final path = tabList?['contentPath'];
    if (path is! String) return const [];
    final body = await _bff.find(path);
    return body == null ? const [] : rtbfParseTabs(body);
  }

  /// Every card of a tab, following the pagination links the server returns.
  Future<List<Object?>> _allCards(String contentPath) async {
    final cards = <Object?>[];
    Map<String, dynamic>? body = await _bff.find(contentPath, query: const {'_limit': _pageSize});
    for (var guard = 0; body != null && guard < _maxPages; guard++) {
      final content = (body['data'] as Map?)?['content'];
      if (content is List) cards.addAll(content);
      final next = (body['links'] as Map?)?['next'];
      body = next is String ? await _bff.find(next) : null;
    }
    return cards;
  }
}
