import 'publicsenat_api.dart';
import 'publicsenat_models.dart';
import 'publicsenat_parser.dart';
import 'publicsenat_seasons.dart';

/// A programme with all the cards that could be loaded and the seasons derived from them.
class PsShow {
  final String slug;
  final PsShowPage page;
  final List<PsCard> cards;

  /// False when the programme has more episodes than the page budget allows loading.
  final bool complete;
  final List<PsSeason> seasons;

  PsShow({required this.slug, required this.page, required this.cards, required this.complete})
    : seasons = groupIntoSeasons(cards, complete: complete);
}

/// Loads and caches what the site's pages hold: programme index, newest videos and programme episodes.
class PublicSenatCatalog {
  /// Pages of a programme fetched at most: the first from the page itself, the rest from "load more".
  static const maxPages = 10;
  static const _ttl = Duration(minutes: 5);

  final PublicSenatApi _api;
  final Map<String, ({DateTime at, Future<Object?> value})> _memo = {};

  PublicSenatCatalog(this._api);

  Future<List<PsProgramme>> programmes() =>
      _cached('programmes', () async => parseProgrammes(await _api.programmes() ?? ''));

  /// The newest videos across programmes, newest first, without repeats.
  Future<List<PsCard>> latest() => _cached('latest', () async => _unique(parseCards(await _api.replays() ?? '')));

  Future<PsProgramme?> programme(String slug) async {
    for (final p in await programmes()) {
      if (p.slug == slug) return p;
    }
    return null;
  }

  /// The programme page alone: header facts and the first batch of episodes. Null when the site has no such programme.
  Future<PsShowPage?> firstPage(String slug) => _cached('page/$slug', () async {
    final html = await _api.show(slug);
    return html == null ? null : parseShowPage(html, slug);
  });

  /// The programme with as many episodes as the page budget allows, or null when the site has no such programme.
  Future<PsShow?> show(String slug) => _cached('show/$slug', () => _loadShow(slug));

  Future<PsShow?> _loadShow(String slug) async {
    final page = await firstPage(slug);
    if (page == null) return null;
    final cards = _unique(page.cards);
    final paging = page.paging;
    var complete = true;

    if (paging != null && page.cards.length >= paging.limit) {
      for (var number = 2; ; number++) {
        final template = await _api.moreCards(paging, number);
        if (template == null) {
          complete = false;
          break;
        }
        final batch = parseCards(template);
        final known = cards.map((c) => c.videoId).toSet();
        final fresh = _unique(batch).where((c) => !known.contains(c.videoId)).toList();
        cards.addAll(fresh);
        if (batch.length < paging.limit) break;
        if (fresh.isEmpty || number >= maxPages) {
          complete = false;
          break;
        }
      }
    }
    return PsShow(slug: slug, page: page, cards: cards, complete: complete);
  }

  List<PsCard> _unique(List<PsCard> cards) {
    final seen = <String>{};
    return [
      for (final card in cards)
        if (seen.add(card.videoId)) card,
    ];
  }

  /// Concurrent callers share one load; a failed load is forgotten so the next call retries.
  Future<T> _cached<T>(String key, Future<T> Function() load) {
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.value as Future<T>;
    final value = load();
    _memo[key] = (at: DateTime.now(), value: value);
    return value.then(
      (v) => v,
      onError: (Object error, StackTrace trace) {
        _memo.remove(key);
        Error.throwWithStackTrace(error, trace);
      },
    );
  }
}
