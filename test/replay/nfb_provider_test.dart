import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nfb/nfb_categories.dart';
import 'package:plezy/replay/providers/nfb/nfb_feed.dart';
import 'package:plezy/replay/providers/nfb/nfb_film_page.dart';
import 'package:plezy/replay/providers/nfb/nfb_ids.dart';
import 'package:plezy/replay/providers/nfb/nfb_images.dart';
import 'package:plezy/replay/providers/nfb/nfb_mapper.dart';
import 'package:plezy/replay/providers/nfb/nfb_page_data.dart';
import 'package:plezy/replay/providers/nfb/nfb_series_page.dart';
import 'package:plezy/replay/providers/nfb/nfb_values.dart';

import 'nfb_test_support.dart';

ReplayRef _ref(String id) => ReplayRef('nfb', id);

List<ReplayTitle> _flat(List<ReplayRail> rails) => [for (final r in rails) ...r.titles];

ReplayTitle _byId(List<ReplayTitle> titles, String slug) => titles.firstWhere((t) => t.ref.nativeId == slug);

/// A series page whose structured data is [json].
String _seriesPage(String json) => '<script type="application/ld+json">$json</script>';

void main() {
  group('NfbProvider browsing', () {
    test('home lists recent, series and film rows in order', () async {
      final rails = await NfbFakeSite().provider().home();
      expect(rails.map((r) => r.id), [
        'recent',
        'series',
        'newest',
        'genre:Animation',
        'genre:Documentary',
        "genre:Children's film",
      ]);
      expect(_flat(rails).every((t) => t.ref.source == 'nfb'), isTrue);
      expect(rails.every((r) => r.titles.isNotEmpty), isTrue);
    });

    test('home keeps its other rows when the feed is down', () async {
      final site = NfbFakeSite()..overrides['/feeds/new_additions/'] = (_) => http.Response('', 500);
      final rails = await site.provider().home();
      expect(rails.map((r) => r.id), isNot(contains('recent')));
      expect(rails.first.id, 'series');
    });

    test('home fails only when every row fails', () async {
      final site = NfbFakeSite();
      for (final path in ['/feeds/new_additions/', '/api/v5/films', '/api/v5/series']) {
        site.overrides[path] = (_) => http.Response('', 500);
      }
      await expectLater(site.provider().home(), throwsA(isA<MediaServerHttpException>()));
    });

    test('a genre page shows newest first and then A to Z', () async {
      final site = NfbFakeSite();
      final rails = await site.provider().category('genre:Documentary');
      expect(rails.map((r) => r.id), ['genre:Documentary:newest', 'genre:Documentary']);
      expect(rails.last.moreBrowseId, 'genre:Documentary');
      final sorts = site.to('/api/v5/films').map((r) => r.url.queryParameters['sort']);
      expect(sorts, [nfbNewestSort, nfbAlphabeticalSort]);
      expect(site.to('/api/v5/films').every((r) => r.url.queryParameters['genre'] == 'Documentary'), isTrue);
      expect(_flat(rails).every((t) => t.genres.contains('Documentary')), isTrue);
    });

    test('an unknown category shows nothing and calls nothing', () async {
      final site = NfbFakeSite();
      expect(await site.provider().category('genre:Nonsense'), isEmpty);
      expect(site.requests, isEmpty);
    });

    test('the menu offers recent films, series and every genre', () async {
      final categories = await NfbFakeSite().provider().categories();
      expect(categories.map((c) => c.id), containsAll(['recent', 'series', 'genre:Animation']));
      expect(categories, hasLength(2 + nfbGenres.length));
    });

    test('the whole catalogue pages through the film catalogue', () async {
      final site = NfbFakeSite();
      final page = await site.provider().listing(replayAllBrowseId, page: 2);
      final request = site.to('/api/v5/films').single;
      expect(request.url.queryParameters['page'], '3');
      expect(request.url.queryParameters['size'], '24');
      expect(request.url.queryParameters['language'], 'en');
      expect(page.totalCount, 4579);
      expect(page.titles, isNotEmpty);
    });

    test('a listing leaves out episodes and works that are for sale only', () async {
      final page = await NfbFakeSite().provider().listing(replayAllBrowseId);
      final ids = page.titles.map((t) => t.ref.nativeId);
      expect(ids, isNot(contains('great-list-of-everything-e1-the-phone')));
      expect(ids, isNot(contains('acting_blind')));
      expect(ids, isNot(contains('alphee_of_the_stars')));
      expect(ids, containsAll(['ryan', 'i_want_a_dog']));
    });

    test('the series listing holds every show on its first page', () async {
      final provider = NfbFakeSite().provider();
      final first = await provider.listing('series');
      expect(first.titles, hasLength(13));
      expect(first.totalCount, 13);
      expect(first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect((await provider.listing('series', page: 1)).titles, isEmpty);
    });

    test('a listing with an unknown id is empty', () async {
      expect((await NfbFakeSite().provider().listing('genre:Nonsense')).titles, isEmpty);
    });

    test('recent additions come from the feed', () async {
      final page = await NfbFakeSite().provider().listing('recent');
      expect(page.titles.first.ref, _ref('les-gens-libres-en'));
      expect(page.totalCount, page.titles.length);
    });
  });

  group('NfbProvider search', () {
    test('films come back ranked by the catalogue without a sort', () async {
      final site = NfbFakeSite();
      final found = await site.provider().search('ryan');
      expect(found.first.ref, _ref('ryan'));
      final request = site.to('/api/v5/films').single;
      expect(request.url.queryParameters['query'], 'ryan');
      expect(request.url.queryParameters.containsKey('sort'), isFalse);
    });

    test('a series whose name matches comes first', () async {
      final found = await NfbFakeSite().provider().search('great list');
      expect(found.first.kind, ReplayKind.show);
      expect(found.first.ref, _ref('s/the-great-list-of-everything-series'));
    });

    test('an episode found by search knows its show', () async {
      final found = await NfbFakeSite().provider().search('phone');
      final episode = _byId(found, 'great-list-of-everything-e1-the-phone');
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('s/the-great-list-of-everything-series'));
    });

    test('an empty query calls nothing and no match returns nothing', () async {
      final site = NfbFakeSite();
      final provider = site.provider();
      expect(await provider.search('   '), isEmpty);
      expect(site.requests, isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });
  });

  group('NfbProvider shows', () {
    test('a series lists its seasons in order with episode counts', () async {
      final seasons = await NfbFakeSite().provider().children(_ref('s/the-great-list-of-everything-series'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.map((s) => s.childCount), [13, 13]);
      expect(seasons.map((s) => s.title), ['Season 1', 'Season 2']);
      expect(seasons.every((s) => s.kind == ReplayKind.season), isTrue);
      expect(seasons.first.showRef, _ref('s/the-great-list-of-everything-series'));
    });

    test('a season lists numbered episodes that play as films', () async {
      final provider = NfbFakeSite().provider();
      final episodes = await provider.children(_ref('s/the-great-list-of-everything-series/2'));
      expect(episodes, hasLength(13));
      expect(episodes.map((e) => e.episodeNumber), [for (var i = 1; i <= 13; i++) i]);
      expect(episodes.first.ref, _ref('great-list-of-everything-season2-the-hot-dog'));
      expect(episodes.first.title, 'The Hot Dog');
      expect(episodes.first.seasonNumber, 2);
      expect(episodes.first.seasonRef, _ref('s/the-great-list-of-everything-series/2'));
      expect(episodes.first.showTitle, 'The Great List of Everything');
    });

    test('a lone "Unique Season" is renamed and a zero episode is kept', () async {
      final provider = NfbFakeSite().provider();
      final seasons = await provider.children(_ref('s/beauty-begins-inside'));
      expect(seasons.single.title, 'Season 1');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [0, 1, 2]);
    });

    test('episode titles drop the show name the site repeats', () async {
      final episodes = await NfbFakeSite().provider().children(_ref('s/beauty-begins-inside/1'));
      expect(episodes.first.title, 'The Pressure Zone');
    });

    test('numbers come from the order when the site omits or repeats them', () {
      final series = nfbParseSeriesPage(
        _seriesPage('''{"@type":"CreativeWorkSeries","name":"Odd","containsSeason":[
          {"name":"Part A","episodes":[
            {"name":"One","url":"https://www.nfb.ca/series/odd/season1/one/"},
            {"name":"Two","url":"https://www.nfb.ca/series/odd/season1/two/"}]},
          {"name":"Part B","season_number":7,"episodes":[
            {"name":"Three","episodeNumber":4,"url":"https://www.nfb.ca/series/odd/season7/three/"},
            {"name":"Four","episodeNumber":4,"url":"https://www.nfb.ca/series/odd/season7/four/"}]}]}'''),
        slug: 'odd',
      )!;
      expect(series.seasons.map((s) => s.season.seasonNumber), [1, 2]);
      expect(series.seasons.first.episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(series.seasons.last.episodes.map((e) => e.episodeNumber), [1, 2]);
    });

    test('a series that lists no season still gets one', () async {
      final site = NfbFakeSite()
        ..overrides['/series/bare/'] = (_) => http.Response(
          _seriesPage('{"@type":"CreativeWorkSeries","name":"Bare"}'),
          200,
          headers: {'content-type': 'text/html'},
        );
      final provider = site.provider();
      final seasons = await provider.children(_ref('s/bare'));
      expect(seasons.single.ref, _ref('s/bare/1'));
      expect(await provider.children(seasons.single.ref), isEmpty);
    });

    test('an unknown or unreadable series is empty, not an error', () async {
      final provider = NfbFakeSite().provider();
      expect(await provider.children(_ref('s/missing')), isEmpty);
      expect(await provider.children(_ref('s/broken')), isEmpty);
      expect(await provider.title(_ref('s/missing')), isNull);
      expect(await provider.children(_ref('s/the-great-list-of-everything-series/9')), isEmpty);
    });

    test('a series calls its page once for every level', () async {
      final site = NfbFakeSite();
      final provider = site.provider();
      await provider.title(_ref('s/the-great-list-of-everything-series'));
      await provider.children(_ref('s/the-great-list-of-everything-series'));
      await provider.children(_ref('s/the-great-list-of-everything-series/1'));
      expect(site.to('/series/the-great-list-of-everything-series/'), hasLength(1));
    });

    test('a film has no children', () async {
      expect(await NfbFakeSite().provider().children(_ref('ryan')), isEmpty);
    });
  });

  group('NfbProvider titles', () {
    test('a film page gives year, exact length, genres and artwork', () async {
      final film = (await NfbFakeSite().provider().title(_ref('i_want_a_dog')))!;
      expect(film.kind, ReplayKind.movie);
      expect(film.title, 'I Want a Dog');
      expect(film.year, 2003);
      expect(film.durationSeconds, 609);
      expect(film.genres, ['Animation', "Children's film"]);
      expect(film.directors, ['Sheldon Cohen']);
      expect(film.summary, contains('"If at first you don’t succeed, try again,"'));
      expect(film.summary, isNot(contains('&')));
      expect(film.posterUrl, endsWith('/jackets/iwantadog_en_keyart_2x3.jpg'));
      expect(film.backdropUrl, endsWith('/thumbs_xlarge/2024/iwantadog_en_keyart_16x9.jpg'));
    });

    test('an episode page knows its show, season and number', () async {
      final episode = (await NfbFakeSite().provider().title(_ref('great-list-of-everything-e1-the-phone')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('s/the-great-list-of-everything-series'));
      expect(episode.seasonRef, _ref('s/the-great-list-of-everything-series/1'));
      expect(episode.showTitle, 'The Great List of Everything');
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.durationSeconds, 164);
      expect(episode.year, 2019);
    });

    test('show and season refs resolve to their titles', () async {
      final provider = NfbFakeSite().provider();
      final show = (await provider.title(_ref('s/the-great-list-of-everything-series')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.childCount, 2);
      expect(show.year, 2019);
      final season = (await provider.title(_ref('s/the-great-list-of-everything-series/2')))!;
      expect(season.kind, ReplayKind.season);
      expect(season.seasonNumber, 2);
    });

    test('a missing film is null and a page without data is null', () async {
      final provider = NfbFakeSite().provider();
      expect(await provider.title(_ref('no-such-film')), isNull);
      expect(await provider.title(_ref('blank')), isNull);
    });
  });

  group('NfbProvider availability', () {
    test('lists mark geo-blocked and upcoming works and drop paid ones', () {
      final body = {
        'items': [
          _film('open'),
          _film('abroad', geoblocked: true),
          _film('shop', isPublic: false),
          _film('soon', isPublic: false, comingSoon: '2026-11-04T00:00:00', geoblocked: true),
          _film('leaving', leavingSoon: '2027-01-25T23:00:00'),
          _film('gone', leavingSoon: '2026-01-25T23:00:00'),
        ],
      };
      final titles = {for (final t in nfbTitlesFromFilms(body, now: nfbTestNow)) t.ref.nativeId: t};
      expect(titles.keys, ['open', 'abroad', 'soon', 'leaving', 'gone']);
      expect(titles['open']!.availability, ReplayAvailability.playable);
      expect(titles['abroad']!.availability, ReplayAvailability.geoBlocked);
      expect(titles['soon']!.availability, ReplayAvailability.upcoming);
      expect(titles['soon']!.airDate, DateTime.utc(2026, 11, 4));
      expect(titles['leaving']!.availability, ReplayAvailability.playable);
      expect(titles['leaving']!.availableUntil, DateTime.utc(2027, 1, 25, 23));
      expect(titles['gone']!.availability, ReplayAvailability.expired);
    });

    test('the recorded catalogue page carries every outcome', () async {
      final page = await NfbFakeSite().provider().listing(replayAllBrowseId);
      final byId = {for (final t in page.titles) t.ref.nativeId: t.availability};
      expect(byId['ryan'], ReplayAvailability.playable);
      expect(byId['1_2_3_coco'], ReplayAvailability.geoBlocked);
      expect(byId['saigon-story'], ReplayAvailability.upcoming);
      expect(page.titles.firstWhere((t) => t.ref.nativeId == 'goldtooth').availableUntil, DateTime.utc(2027, 5, 8));
    });

    test('malformed catalogue entries are skipped, not thrown', () {
      final body = {
        'items': [
          'text',
          {'slug': 'no-title'},
          {'slug': 'ok', 'title': ' Fine ', 'thumbnail': 5, 'duration': 'long', 'year': null, 'directors': 'x'},
        ],
      };
      final titles = nfbTitlesFromFilms(body, now: nfbTestNow);
      expect(titles.single.title, 'Fine');
      expect(titles.single.durationSeconds, isNull);
      expect(nfbTitlesFromFilms({'items': 'oops'}), isEmpty);
      expect(nfbTitlesFromFilms({}), isEmpty);
    });
  });

  group('NfbProvider playback', () {
    test('a playable film yields one clear HLS stream with no fragment', () async {
      final playback = await NfbFakeSite().provider().playback(_ref('plain'));
      expect(playback.isPlayable, isTrue);
      final stream = playback.streams.single;
      expect(stream.url.host, 'd3acx5b8mnvbua.cloudfront.net');
      expect(stream.url.path, endsWith('.m3u8'));
      expect(stream.url.hasFragment, isFalse);
      expect(stream.url.queryParameters.keys, containsAll(['Policy', 'Signature', 'Key-Pair-Id']));
      expect(stream.label, 'EN');
      expect(stream.headers, isEmpty);
    });

    test('a film with audio description offers it as a second stream', () async {
      final provider = NfbFakeSite().provider();
      for (final slug in ['ryan', 'i_want_a_dog']) {
        final playback = await provider.playback(_ref(slug));
        expect(playback.streams.map((s) => s.label), ['EN', 'AD'], reason: slug);
        expect(playback.streams.last.url.path, contains('_aen'));
      }
    });

    test('the player page is fetched at every play, never reused', () async {
      final site = NfbFakeSite();
      final provider = site.provider();
      await provider.playback(_ref('ryan'));
      await provider.playback(_ref('ryan'));
      expect(site.to('/film/ryan/embed/player/'), hasLength(2));
    });

    test('a film blocked in the viewer country says so', () async {
      final playback = await NfbFakeSite().provider().playback(_ref('1_2_3_coco'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('not available for free viewing'));
    });

    test('a film that is for sale only is not playable and says why', () async {
      final playback = await NfbFakeSite().provider().playback(_ref('acting_blind'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('bought or rented'));
    });

    test('a film the site no longer has is reported as expired', () async {
      final playback = await NfbFakeSite().provider().playback(_ref('gone-forever'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing and pauses requests', () async {
      final site = NfbFakeSite();
      final provider = site.provider();
      final playback = await provider.playback(_ref('limited'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
      final before = site.requests.length;
      final again = await provider.playback(_ref('ryan'));
      expect(again.isPlayable, isFalse);
      expect(site.requests.length, before);
    });

    test('a damaged player configuration is unavailable, not a crash', () async {
      final playback = await NfbFakeSite().provider().playback(_ref('mangled'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('a show or season is never played directly', () async {
      final provider = NfbFakeSite().provider();
      expect((await provider.playback(_ref('s/beauty-begins-inside'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('s/beauty-begins-inside/1'))).isPlayable, isFalse);
    });
  });

  group('NfbApi', () {
    test('every request names the app in its user agent', () async {
      final site = NfbFakeSite();
      await site.provider().home();
      await site.provider().playback(_ref('ryan'));
      expect(site.requests, isNotEmpty);
      const agent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
      bool named(http.Request r) =>
          r.headers.entries.any((e) => e.key.toLowerCase() == 'user-agent' && e.value == agent);
      expect(site.requests.every(named), isTrue);
    });

    test('repeating a catalogue request within minutes is served from memory', () async {
      final site = NfbFakeSite();
      final provider = site.provider();
      await provider.listing(replayAllBrowseId);
      await provider.listing(replayAllBrowseId);
      expect(site.to('/api/v5/films'), hasLength(1));
    });

    test('requests are spaced by the configured interval', () async {
      final site = NfbFakeSite();
      final api = site.api(interval: const Duration(milliseconds: 60));
      final watch = Stopwatch()..start();
      await Future.wait([api.series(), api.recentFeed(), api.playerPage('ryan')]);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });

    test('an answer that is not a JSON object is an error', () async {
      final site = NfbFakeSite()..overrides['/api/v5/series'] = (_) => http.Response('[1]', 200);
      await expectLater(site.api().series(), throwsA(isA<MediaServerHttpException>()));
    });
  });

  group('NFB page data', () {
    test('json-ld readers skip damaged blocks and flatten lists', () {
      const html = '''
        <script type="application/ld+json">{ broken</script>
        <script type="application/ld+json">[{"@type":"Movie"},{"@type":["Episode","VideoObject"]}]</script>
        <script type="text/javascript">var x = 1;</script>''';
      final blocks = nfbJsonLd(html);
      expect(blocks, hasLength(2));
      expect(nfbHasType(blocks.last, 'Episode'), isTrue);
      expect(nfbHasType(blocks.first, 'Episode'), isFalse);
      expect(nfbJsonLd('<html></html>'), isEmpty);
    });

    test('the data layer reads escaped quotes and both quote styles', () {
      const html = r'''
        <script>dataLayer.push({
          'nfb_version_title': 'Don\'t Look',
          'nfb_version_year': '1999',
          'nfb_version_duration': '75',
          'nfb_version_category': {'en': ['Animation', "Children's film", ''], 'fr': ['Film']},
        });</script>''';
      final layer = nfbDataLayer(html);
      expect(layer.fields['nfb_version_title'], "Don't Look");
      expect(layer.year, 1999);
      expect(layer.durationSeconds, 75);
      expect(layer.categories, ['Animation', "Children's film"]);
    });

    test('a page without a data layer gives empty values', () {
      final layer = nfbDataLayer('<html><script>var a = 1;</script></html>');
      expect(layer.fields, isEmpty);
      expect(layer.year, isNull);
      expect(layer.durationSeconds, isNull);
    });

    test('player options survive text after them and fail quietly when cut', () {
      expect(nfbPlayerOptions('x\nwindow.IFRAME_OPTIONS = {"source": "https://a.test/m.m3u8"}\nwindow.LOCALE = "en"'), {
        'source': 'https://a.test/m.m3u8',
      });
      expect(nfbPlayerOptions('window.IFRAME_OPTIONS = {"source": '), isNull);
      expect(nfbPlayerOptions('nothing'), isNull);
    });

    test('the overlay notice reads its message and purchase offers', () {
      final notice = nfbOverlayNotice(nfbFixture('embed_paid.html'));
      expect(notice.offers, {'BUY', 'DVD'});
      expect(notice.messageId, isNull);
      final blocked = nfbOverlayNotice(nfbFixture('embed_geoblocked.html'));
      expect(blocked.messageId, 'MESSAGE_GEOBLOCKED');
    });

    test('a film page with only a data layer still gives a title', () {
      const html = '''<script>dataLayer.push({'nfb_version_title': 'Bare', 'nfb_version_year': '1950'});</script>''';
      final title = nfbTitleFromFilmPage(html, slug: 'bare')!;
      expect(title.title, 'Bare');
      expect(title.year, 1950);
      expect(nfbTitleFromFilmPage('<html></html>', slug: 'none'), isNull);
    });
  });

  group('NFB feed', () {
    test('cards carry the title, picture and publication time', () {
      final titles = nfbTitlesFromFeed(nfbFixture('feed_new_additions.xml'));
      expect(titles, isNotEmpty);
      final first = titles.first;
      expect(first.ref, _ref('les-gens-libres-en'));
      expect(first.title, 'Les gens libres (English Version)');
      expect(first.airDate, DateTime.utc(2025, 10, 23, 19, 30, 22));
      expect(first.backdropUrl, startsWith(nfbImageHost));
      expect(first.backdropUrl, isNot(contains('?')));
      expect(titles.any((t) => t.title == '\u019Ba\u0294uuk\u02B7iath\u0323 Dugout Canoe'), isTrue);
    });

    test('a feed that is not XML or has no usable items is empty', () {
      expect(nfbTitlesFromFeed('<rss><channel><item>'), isEmpty);
      expect(nfbTitlesFromFeed('not xml'), isEmpty);
      expect(nfbTitlesFromFeed('<rss><channel><item><title>No link</title></item></channel></rss>'), isEmpty);
    });

    test('repeated items appear once', () {
      const item = '<item><title>A</title><link>https://www.nfb.ca/film/a/</link></item>';
      expect(nfbTitlesFromFeed('<rss><channel>$item$item</channel></rss>'), hasLength(1));
    });
  });

  group('NFB images and ids', () {
    test('a width alone keeps the aspect ratio and is capped', () {
      const ref = '${nfbImageHost}jackets/a.jpg';
      expect(nfbImageUrl(ref, width: 300), '$ref?w=300');
      expect(nfbImageUrl(ref, width: 9000), '$ref?w=2048');
      expect(nfbImageUrl(ref, height: 400), '$ref?h=400');
      expect(nfbImageUrl(ref), '$ref?w=720');
      expect(nfbImageUrl('$ref?w=704&h=396', width: 200, height: 300), '$ref?w=200');
    });

    test('references from paths are encoded and owned, others are left alone', () {
      final ref = nfbImageFromPath('thumbs_xlarge/2026/KEYART_APRÈS.jpg')!;
      expect(ref, '${nfbImageHost}thumbs_xlarge/2026/KEYART_APR%C3%88S.jpg');
      expect(isNfbImage(ref), isTrue);
      expect(isNfbImage('https://example.test/a.jpg'), isFalse);
      expect(nfbImageUrl('https://example.test/a.jpg', width: 100), 'https://example.test/a.jpg');
      expect(nfbImageFromPath('  '), isNull);
      expect(nfbImageFromPath(null), isNull);
    });

    test('the recorded catalogue builds artwork from its paths', () async {
      final page = await NfbFakeSite().provider().listing(replayAllBrowseId);
      final deluge = _byId(page.titles, 'after-me-the-deluge-short-film-mounir');
      expect(deluge.posterUrl, contains('KEYART_APR%C3%88S_MOI'));
      final ryan = _byId(page.titles, 'ryan');
      expect(ryan.posterUrl, contains('/jackets/'));
      expect(ryan.backdropUrl, contains('/thumbs_xlarge/'));
    });

    test('series ids split into slug and season', () {
      expect(parseNfbSeriesId('s/great'), (slug: 'great', season: null));
      expect(parseNfbSeriesId('s/great/2'), (slug: 'great', season: 2));
      expect(parseNfbSeriesId('s/great/x'), isNull);
      expect(parseNfbSeriesId('s/'), isNull);
      expect(parseNfbSeriesId('s/a/1/2'), isNull);
      expect(parseNfbSeriesId('ryan'), isNull);
      expect(nfbSeasonRef('great', 2).toString(), 'nfb:s/great/2');
      expect(ReplayRef.tryParse('nfb:s/great/2'), nfbSeasonRef('great', 2));
    });

    test('addresses give film and series slugs', () {
      const url = 'https://www.nfb.ca/series/the-great-list/season1/e1-the-phone/';
      expect(nfbSlugFromUrl(url), 'e1-the-phone');
      expect(nfbSeriesSlugFromUrl(url), 'the-great-list');
      expect(nfbSlugFromUrl(null), isNull);
      expect(nfbSeriesSlugFromUrl('https://www.nfb.ca/film/ryan/'), isNull);
    });
  });

  group('NFB text values', () {
    test('synopses lose tags and numeric character references', () {
      expect(nfbText('She&#x27;s <em>here</em> &#8212; &quot;now&quot;\r\n\r\nNext'), 'She\'s here — "now"\n\nNext');
      expect(nfbText('  '), isNull);
      expect(nfbText(null), isNull);
      expect(nfbText('&#99999999;x'), 'x');
    });

    test('iso durations and integers are read leniently', () {
      expect(nfbIsoSeconds('PT10M'), 600);
      expect(nfbIsoSeconds('PT1H02M03S'), 3723);
      expect(nfbIsoSeconds('PT0S'), isNull);
      expect(nfbIsoSeconds('ten minutes'), isNull);
      expect(nfbInt(' 12 '), 12);
      expect(nfbInt(3.0), 3);
      expect(nfbInt('x'), isNull);
    });
  });
}

Map<String, dynamic> _film(
  String slug, {
  bool isPublic = true,
  bool geoblocked = false,
  String? comingSoon,
  String? leavingSoon,
}) => {
  'slug': slug,
  'title': slug,
  'thumbnail': 'thumbs_xlarge/2024/$slug.jpg',
  'availability': {'is_public': isPublic},
  'geoblocked': geoblocked,
  'coming_soon': comingSoon,
  'leaving_soon': leavingSoon,
  'part_of': <Object>[],
};
