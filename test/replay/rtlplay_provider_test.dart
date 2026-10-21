import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_api.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_labels.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/rtlplay';
const _bates = '0fda66b9-e270-4ffd-b4ca-f0687711a7c3';
const _film = 'd1cb72af-01ae-49ef-84bc-d41dc7a87e9b';
const _documentary = '7fa44e55-91b1-47e3-a59c-bc12bac77d42';
const _news = '75778047-34c8-41f2-b104-b05945d20deb';
const _twoSummers = 'e6276d61-acc5-43cf-a05d-bf35fd0c81ac';
const _batesS3Episode1 = 'e28a86f0-6f2a-47b6-a5c5-f8cdf9a42a1b';
const _newsLatest = '0f536cef-35fe-46d2-920a-8156e33b059d';

String _fixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

http.Response _json(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

/// The detail fixture for a programme and the season index asked for; other seasons do not exist.
String? _detail(String id, String? season) => switch ((id, season)) {
  (_bates, null || '1') => 'show_series_season1',
  (_bates, '3') => 'show_series_season3',
  (_film, null) => 'show_film',
  (_documentary, null) => 'show_documentary',
  (_news, null || '2026') => 'show_magazine_news',
  (_twoSummers, null || '1') => 'show_series_pg12_rating',
  _ => null,
};

/// Serves recorded RTL Play responses by path; anything else is the not-found body.
http.Response _route(http.Request request) {
  final path = request.url.path.replaceFirst('/RTL_PLAY/', '');
  final query = request.url.queryParameters;
  if (path == 'storefronts/accueil') return _json(_fixture('home'));
  if (path == 'storefronts/series') return _json(_fixture('storefront_series'));
  if (path.startsWith('storefronts/') && path.contains('/detail/')) return _json(_fixture('row_detail'));
  if (path.startsWith('storefronts/')) return _json('{"rows":[]}');
  if (path.startsWith('detail3/')) {
    final name = _detail(path.substring('detail3/'.length), query['selectedSeasonIndex']);
    return name == null ? _json('{}', 404) : _json(_fixture(name));
  }
  if (path == 'search') {
    return _json(switch (query['query']) {
      'depardieu' => _fixture('search_person'),
      'zzzz' => _fixture('search_fallback_no_results'),
      _ => _fixture('search'),
    });
  }
  return _json('{}', 404);
}

RtlPlayProvider _provider({http.Response Function(http.Request)? route, List<http.Request>? log}) {
  final client = MediaServerHttpClient(
    client: MockClient((request) async {
      log?.add(request);
      return (route ?? _route)(request);
    }),
  );
  return RtlPlayProvider.withApi(RtlPlayApi(client));
}

ReplayRef _ref(String id) => ReplayRef('rtlplay', id);

void main() {
  group('RtlPlayProvider source', () {
    test('is a French source that plays when signed in', () {
      final source = _provider().source;
      expect((source.id, source.name, source.language), ('rtlplay', 'RTL Play', 'fr'));
      expect(source.support, ReplayPlaybackSupport.partial);
    });

    test('offers the storefronts as categories', () async {
      final categories = await _provider().categories();
      expect(categories.map((c) => c.id), ['series', 'films', 'documentaires', 'divertissement', 'sport']);
    });
  });

  group('RtlPlayProvider requests', () {
    test('every request identifies the app and carries the version header', () async {
      final log = <http.Request>[];
      await _provider(log: log).home();
      expect(log.single.headers['x-app-version'], '25');
      expect(log.single.headers['User-Agent'], startsWith('Plezy-Replay'));
      expect(log.single.url.queryParameters, containsPair('hideBannerRow', 'true'));
    });

    test('a refused app version is retried with the next accepted one', () async {
      final log = <http.Request>[];
      final provider = _provider(
        log: log,
        route: (r) => r.headers['x-app-version'] == '25' ? http.Response('', 426) : _route(r),
      );
      expect(await provider.home(), isNotEmpty);
      expect(log.map((r) => r.headers['x-app-version']), ['25', '26']);
      await provider.category('series');
      expect(log.last.headers['x-app-version'], '26');
    });

    test('a catalogue that refuses every version fails with a clear error', () async {
      final provider = _provider(route: (_) => http.Response('', 426));
      expect(provider.home(), throwsA(isA<RtlPlayVersionRejectedException>()));
    });

    test('responses are cached for a few minutes', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      await provider.home();
      await provider.home();
      expect(log, hasLength(1));
    });

    test('rate limiting surfaces the retry delay', () async {
      final provider = _provider(route: (_) => http.Response('', 429, headers: {'retry-after': '30'}));
      await expectLater(
        provider.search('bates'),
        throwsA(
          isA<RtlPlayRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30)),
        ),
      );
    });
  });

  group('RtlPlayProvider browsing', () {
    test('home keeps card rows and drops banners, tiles and live channels', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.title), ['À regarder maintenant', 'Séries immanquables', 'Films', 'Top 10']);
      expect(rails.every((r) => r.titles.every((t) => t.ref.source == 'rtlplay')), isTrue);
    });

    test('rows with a detail page link to their full content', () async {
      final rails = await _provider().home();
      expect(rails.first.moreBrowseId, 'row/accueil/${rails.first.id}');
      expect(rails.last.moreBrowseId, isNull);
    });

    test('portrait rows give a poster and landscape rows a backdrop', () async {
      final rails = await _provider().home();
      final portrait = rails.first.titles.first;
      final landscape = rails[1].titles.first;
      expect(portrait.posterUrl, contains('/_fitwidth/320'));
      expect(portrait.backdropUrl, contains('/_fitwidth/1400'));
      expect(landscape.posterUrl, isNull);
      expect(landscape.backdropUrl, contains('/_fitwidth/426'));
    });

    test('top 10 cards use the separate portrait and landscape images', () async {
      final top = (await _provider().home()).last.titles.first;
      expect(top.posterUrl, isNotNull);
      expect(top.backdropUrl, isNotNull);
      expect(top.posterUrl, isNot(top.backdropUrl));
    });

    test('cards tell films from series by their labels', () async {
      final titles = [for (final r in await _provider().home()) ...r.titles];
      final byName = {for (final t in titles) t.title: t};
      expect(byName['Bates Motel']!.kind, ReplayKind.show);
      expect(byName['Bates Motel']!.childCount, 5);
      expect(byName['Maison de retraite']!.kind, ReplayKind.movie);
      expect(byName['Maison de retraite']!.durationSeconds, 93 * 60);
      expect(byName['Maison de retraite']!.year, 2020);
    });

    test('cards are marked as needing a login before playback is asked', () async {
      final titles = [for (final r in await _provider().home()) ...r.titles];
      expect(titles.every((t) => t.availability == ReplayAvailability.loginRequired), isTrue);
    });

    test('a category page maps its storefront rows', () async {
      final rails = await _provider().category('series');
      expect(rails.map((r) => r.title), contains('Séries françaises'));
      expect(rails.any((r) => r.title == 'Top 10 séries'), isTrue);
    });

    test('a row listing returns its whole content in pages', () async {
      final provider = _provider();
      final rail = (await provider.category('series')).first;
      final page = await provider.listing(rail.moreBrowseId!);
      expect(page.totalCount, 5);
      expect(page.titles.map((t) => t.title), contains('Magnum'));
      expect((await provider.listing(rail.moreBrowseId!, page: 1)).titles, isEmpty);
    });

    test('the whole catalogue lists each programme once, sorted by title', () async {
      final page = await _provider().listing(replayAllBrowseId);
      final ids = page.titles.map((t) => t.ref.nativeId).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(page.totalCount, greaterThan(page.titles.length - 1));
      final keys = page.titles.map((t) => sortKey(t.title)).toList();
      expect(keys, orderedEquals([...keys]..sort()));
    });

    test('an unknown listing is empty', () async {
      expect((await _provider().listing('nope')).titles, isEmpty);
    });
  });

  group('RtlPlayProvider search', () {
    test('programmes found by title become cards', () async {
      final hits = await _provider().search('alerte');
      expect(hits.map((t) => t.title), ['APB - Alerte d\'urgence', 'Alerte à l\'hôtel : 30 jours pour tout relancer']);
      expect(hits.first.kind, ReplayKind.show);
      expect(hits.first.backdropUrl, contains('/_fitwidth/426'));
    });

    test('a person search returns the programmes they appear in', () async {
      final hits = await _provider().search('depardieu');
      expect(hits.single.ref, _ref(_film));
      expect(hits.single.kind, ReplayKind.movie);
    });

    test('the popular-searches fallback is not a result', () async {
      expect(await _provider().search('zzzz'), isEmpty);
    });

    test('a blank query makes no request', () async {
      final log = <http.Request>[];
      expect(await _provider(log: log).search('   '), isEmpty);
      expect(log, isEmpty);
    });
  });

  group('RtlPlayProvider shows', () {
    test('a series lists its seasons with the episode count of the listed one', () async {
      final seasons = await _provider().children(_ref(_bates));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5]);
      expect(seasons.map((s) => s.title), ['Saison 1', 'Saison 2', 'Saison 3', 'Saison 4', 'Saison 5']);
      expect(seasons.map((s) => s.childCount), [10, null, null, null, null]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref(_bates)), isTrue);
      expect(seasons.first.ref, _ref('$_bates/1'));
    });

    test('a season lists numbered episodes with clean titles and parents', () async {
      final episodes = await _provider().children(_ref('$_bates/3'));
      expect(episodes, hasLength(10));
      final first = episodes.first;
      expect(first.ref, _ref('$_bates/3/$_batesS3Episode1'));
      expect(first.title, 'Une morte dans la famille');
      expect(first.episodeNumber, 1);
      expect(first.seasonNumber, 3);
      expect(first.durationSeconds, 2467);
      expect(first.seasonRef, _ref('$_bates/3'));
      expect(first.showRef, _ref(_bates));
      expect(first.showTitle, 'Bates Motel');
      expect(episodes.map((e) => e.episodeNumber), [for (var i = 1; i <= 10; i++) i]);
    });

    test('a season that does not exist has no episodes', () async {
      expect(await _provider().children(_ref('$_bates/9')), isEmpty);
    });

    test('a magazine has one season per year and episodes newest first', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref(_news));
      expect(seasons.single.title, '2026');
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.ref, _ref('$_news/2026'));

      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(7));
      expect(episodes.first.ref, _ref('$_news/2026/$_newsLatest'));
      expect(episodes.first.title, 'RTL info 19 heures (20/10/2026)');
      expect(episodes.first.episodeNumber, 293);
      expect(episodes.first.seasonNumber, 1);
      expect(episodes.first.airDate, DateTime.utc(2026, 10, 20));
      expect(episodes.map((e) => e.episodeNumber), [293, 292, 291, 290, 289, 288, 287]);
    });

    test('placeholder episode titles are kept after the number is removed', () async {
      final episodes = await _provider().children(_ref('$_twoSummers/1'));
      expect(episodes.first.title, 'Episode 01');
      expect(episodes.first.episodeNumber, 1);
    });

    test('a film is a movie with no children', () async {
      final provider = _provider();
      final film = (await provider.title(_ref(_film)))!;
      expect(film.kind, ReplayKind.movie);
      expect(film.durationSeconds, 5612);
      expect(film.year, 2020);
      expect(film.genres, ['Comédie']);
      expect(film.directors, ['Thomas Gilou']);
      expect(film.cast, contains('Gérard Depardieu'));
      expect(film.backdropUrl, contains('persgroep.net'));
      expect(film.logoUrl, isNotNull);
      expect(await provider.children(film.ref), isEmpty);
    });

    test('a one-off documentary is a movie too', () async {
      final documentary = (await _provider().title(_ref(_documentary)))!;
      expect(documentary.kind, ReplayKind.movie);
      expect(documentary.durationSeconds, 3282);
    });

    test('a show page carries its metadata and age rating', () async {
      final provider = _provider();
      final show = (await provider.title(_ref(_twoSummers)))!;
      expect((show.kind, show.title, show.childCount), (ReplayKind.show, 'Two Summers', 1));
      expect(show.contentRating, '12+');
      expect(show.year, 2021);
      expect(show.cast, isNotEmpty);
      expect((await provider.title(_ref(_bates)))!.contentRating, isNull);
    });

    test('the poster seen on a card is kept for the show page', () async {
      final provider = _provider();
      final card = (await provider.category('series')).first.titles.first;
      expect(card.posterUrl, isNotNull);
      http.Response route(http.Request r) =>
          r.url.path.endsWith(card.ref.nativeId) ? _json(_fixture('show_film')) : _route(r);
      final withDetail = _provider(route: route);
      await withDetail.category('series');
      expect((await withDetail.title(card.ref))!.posterUrl, card.posterUrl);
      expect((await provider.title(_ref(_film)))!.posterUrl, isNull);
    });

    test('a season and an episode can be opened by id', () async {
      final provider = _provider();
      final season = (await provider.title(_ref('$_bates/3')))!;
      expect((season.kind, season.title, season.childCount), (ReplayKind.season, 'Saison 3', 10));
      final episode = (await provider.title(_ref('$_bates/3/$_batesS3Episode1')))!;
      expect((episode.kind, episode.episodeNumber, episode.seasonNumber), (ReplayKind.episode, 1, 3));
    });

    test('unknown programmes, seasons and episodes are null', () async {
      final provider = _provider();
      expect(await provider.title(_ref('missing')), isNull);
      expect(await provider.title(_ref('$_bates/9')), isNull);
      expect(await provider.title(_ref('$_bates/3/gone')), isNull);
      expect(await provider.title(_ref('$_bates/x')), isNull);
      expect(await provider.children(_ref('missing')), isEmpty);
    });
  });

  group('RtlPlayProvider playback', () {
    test('an episode needs a login and says so', () async {
      final playback = await _provider().playback(_ref('$_bates/3/$_batesS3Episode1'));
      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('RTL account'));
    });

    test('a film needs a login too', () async {
      expect((await _provider().playback(_ref(_film))).availability, ReplayAvailability.loginRequired);
    });

    test('nothing is requested from the stream service', () async {
      final log = <http.Request>[];
      await _provider(log: log).playback(_ref('$_bates/3/$_batesS3Episode1'));
      expect(log.every((r) => r.url.host == 'lfvp-api.dpgmedia.net'), isTrue);
    });

    test('an episode that left the catalogue is expired', () async {
      expect((await _provider().playback(_ref('$_bates/3/gone'))).availability, ReplayAvailability.expired);
      expect((await _provider().playback(_ref('missing'))).availability, ReplayAvailability.expired);
    });

    test('shows and seasons are never played directly', () async {
      final provider = _provider();
      expect((await provider.playback(_ref(_bates))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(_ref('$_bates/3'))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(_ref('a/b/c/d'))).isPlayable, isFalse);
    });

    test('rate limiting is reported without throwing', () async {
      final provider = _provider(route: (_) => http.Response('', 429, headers: {'retry-after': '12'}));
      final playback = await provider.playback(_ref(_film));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('12'));
    });
  });

  group('RtlPlay images', () {
    test('signed catalogue images are used exactly as given', () {
      final provider = _provider();
      const url = 'https://images2.persgroep.net/rcs/abc/diocontent/1/_fitwidth/426?appId=x&quality=0.8';
      expect(provider.ownsImage(url), isTrue);
      expect(provider.imageUrl(url, width: 800, height: 450), url);
    });

    test('overlay badges are owned, other hosts are not', () {
      final provider = _provider();
      expect(provider.ownsImage('https://lfvp-static-overlays.dpgmedia.net/5/259214730'), isTrue);
      expect(provider.ownsImage('https://api-cdn.arte.tv/img/v2/image/abc/__SIZE__'), isFalse);
    });
  });
}
