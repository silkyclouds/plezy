import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'lrt_test_support.dart';

/// Browsing, search and the programme -> season -> recording structure, over recorded pages and feeds.
void lrtCatalogCases() {
  group('LrtProvider browsing', () {
    test('the source is a clear Lithuanian one', () {
      final source = lrtProviderOver(LrtFakeSite()).source;
      expect(source.id, 'lrt');
      expect(source.name, 'LRT');
      expect(source.language, 'lt');
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 30);
    });

    test('categories are the site sections with unique ids', () async {
      final categories = await lrtProviderOver(LrtFakeSite()).categories();
      expect(categories.first.id, 'new');
      expect(categories.map((c) => c.id), contains('filmai'));
      expect(categories.map((c) => c.id).toSet(), hasLength(categories.length));
    });

    test('home rows are the newest, films, children, shows and news', () async {
      final rails = await lrtProviderOver(LrtFakeSite()).home();
      expect(rails.map((r) => r.id), ['new', 'filmai', 'vaikams', 'pramogos', 'news']);
      expect(rails.map((r) => r.moreBrowseId), ['new', 'filmai', 'vaikams', 'pramogos', null]);
      expect(rails[1].titles.every((t) => t.kind == ReplayKind.movie), isTrue);
      expect([for (final r in rails) ...r.titles].every((t) => t.ref.source == 'lrt' && t.isPlayable), isTrue);
    });

    test('a card has its date, programme and a resizable picture', () async {
      final card = (await lrtProviderOver(LrtFakeSite()).home()).first.titles.first;
      expect(card.ref, lrtRecording('2000901019'));
      expect(card.title, 'Žinios');
      expect(card.subtitle, '2026-10-22 08:44');
      expect(card.airDate, DateTime.utc(2026, 10, 22, 5, 44));
      expect(card.showTitle, 'Žinios');
      expect(card.backdropUrl, 'https://www.lrt.lt/img/2026/10/22/2518160-705862-{WxH}.jpg');
      expect(card.availability, ReplayAvailability.playable);
    });

    test('a failing secondary row is skipped, a failing first row is not', () async {
      final site = LrtFakeSite()..overrides['/mediateka/vaikams'] = (_) => http.Response('', 500);
      final rails = await lrtProviderOver(site).home();
      expect(rails.map((r) => r.id), ['new', 'filmai', 'pramogos', 'news']);

      final broken = LrtFakeSite()..overrides['/mediateka'] = (_) => http.Response('', 500);
      await expectLater(lrtProviderOver(broken).home(), throwsA(isA<MediaServerHttpException>()));
    });

    test('a feed that is not XML leaves its row out', () async {
      final site = LrtFakeSite()..overrides['/mediateka/pramogos'] = (_) => LrtFakeSite.xml('<rss><channel><item>');
      final rails = await lrtProviderOver(site).home();
      expect(rails.map((r) => r.id), ['new', 'filmai', 'vaikams', 'news']);
    });

    test('a category is one row of its feed, an unknown one is empty', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final rails = await provider.category('filmai');
      expect(rails.single.titles, hasLength(4));
      expect(rails.single.titles.every((t) => t.kind == ReplayKind.movie), isTrue);
      expect(await provider.category('nonsense'), isEmpty);
    });

    test('the whole catalogue lists programmes A to Z with decoded names', () async {
      final page = await lrtProviderOver(LrtFakeSite()).listing(replayAllBrowseId);
      expect(page.totalCount, 18);
      expect(page.titles, hasLength(18));
      expect(page.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(page.titles.first.ref, lrtRef('1-000-pasaulio-stebuklu-su-vertimu-i-gestu-k'));
      expect(page.titles.map((t) => t.title), contains('Vakaro žinios & orai'));
    });

    test('listings past the end are empty and the index is fetched once', () async {
      final site = LrtFakeSite();
      final provider = lrtProviderOver(site);
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
      expect((await provider.listing(replayAllBrowseId, page: 2)).totalCount, 18);
      expect(site.requestsTo('tv-laidos'), 1);
    });

    test('a section listing pages through its feed', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final first = await provider.listing('filmai');
      expect(first.titles, hasLength(4));
      expect(first.totalCount, 4);
      expect((await provider.listing('filmai', page: 1)).titles, isEmpty);
      expect((await provider.listing('nonsense')).totalCount, 0);
    });

    test('a site that sends an unknown feed 404 gives empty rows, not errors', () async {
      final site = LrtFakeSite()..overrides['/mediateka/filmai'] = (_) => http.Response('Not found', 404);
      expect(await lrtProviderOver(site).category('filmai'), isEmpty);
    });
  });

  group('LrtProvider search', () {
    test('programmes come first, then recordings placed in their season', () async {
      final site = LrtFakeSite();
      final titles = await lrtProviderOver(site).search('gamta');
      expect(titles.first.kind, ReplayKind.show);
      expect(titles.first.ref, lrtRef('mylekime-gamta'));
      expect(titles.skip(1), hasLength(4));
      final recording = titles[1];
      expect(recording.ref, lrtRecording('2000900035'));
      expect(recording.kind, ReplayKind.episode);
      expect(recording.showRef, lrtRef('labas-rytas-lietuva'));
      expect(recording.seasonRef, lrtRef('labas-rytas-lietuva/2026'));
      expect(recording.showTitle, 'Labas rytas, Lietuva');
    });

    test('a second page is read when there are more than ten hits', () async {
      final site = LrtFakeSite();
      await lrtProviderOver(site).search('gamta');
      expect(site.requestsTo('page=2'), 1);
    });

    test('a blank query asks nothing, no hits gives nothing', () async {
      final site = LrtFakeSite();
      final provider = lrtProviderOver(site);
      expect(await provider.search('   '), isEmpty);
      expect(site.requests, isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('a search answer that is not JSON gives nothing', () async {
      final site = LrtFakeSite()..overrides['/api/json/search'] = (_) => LrtFakeSite.html('<html>oops</html>');
      expect(await lrtProviderOver(site).search('gamta'), isEmpty);
    });
  });

  group('LrtProvider shows', () {
    test('a show lists its seasons oldest first with numbers', () async {
      final seasons = await lrtProviderOver(LrtFakeSite()).children(lrtRef('zinios'));
      expect(seasons.map((s) => s.title), ['2022', '2023', '2024', '2024-2', '2025', '2026']);
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5, 6]);
      expect(seasons.map((s) => s.ref.nativeId), contains('zinios/2024-2'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == lrtRef('zinios')), isTrue);
      expect(seasons.first.year, 2022);
    });

    test('a show with one season reports its recording count', () async {
      final seasons = await lrtProviderOver(LrtFakeSite()).children(lrtRef('mylekime-gamta'));
      expect(seasons.single.ref, lrtRef('mylekime-gamta/1975'));
      expect(seasons.single.childCount, 1);
      expect(seasons.single.seasonNumber, 1);
    });

    test('a show without seasons gets one that holds every recording', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final seasons = await provider.children(lrtRef('be-sezonu'));
      expect(seasons.single.ref, lrtRef('be-sezonu/_all'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Mylėkime gamtą');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.single.seasonRef, seasons.single.ref);
      expect(episodes.single.episodeNumber, 1);
    });

    test('an unknown show has no seasons and no title', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      expect(await provider.children(lrtRef('no-such-show')), isEmpty);
      expect(await provider.title(lrtRef('no-such-show')), isNull);
      expect(await provider.children(lrtRef('no-such-show/2020')), isEmpty);
    });

    test('a show page that carries no payload is an unknown show', () async {
      final site = LrtFakeSite()
        ..overrides['/mediateka/video/zinios'] = (_) => LrtFakeSite.html('<html><body>redesign</body></html>');
      expect(await lrtProviderOver(site).children(lrtRef('zinios')), isEmpty);
    });

    test('a season lists its recordings oldest first with parents', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final episodes = await provider.children(lrtRef('zinios/2025'));
      expect(episodes.map((e) => e.ref.nativeId), [
        'rec:2000603114',
        'rec:2000603117',
        'rec:2000603118',
        'rec:2000603119',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.every((e) => e.kind == ReplayKind.episode), isTrue);
      expect(episodes.first.seasonNumber, 5);
      expect(episodes.first.seasonRef, lrtRef('zinios/2025'));
      expect(episodes.first.showRef, lrtRef('zinios'));
      expect(episodes.first.showTitle, 'Žinios');
    });

    test('recordings take their number from the title when it states one', () async {
      final episodes = await lrtProviderOver(LrtFakeSite()).children(lrtRef('pazvelk-i-profesija-kitaip/2015'));
      expect(episodes.map((e) => e.episodeNumber), [99, 100, 101, 102]);
      expect(episodes.map((e) => e.ref.nativeId), [
        'rec:1013690998',
        'rec:1013691456',
        'rec:1013691890',
        'rec:1013692322',
      ]);
      expect(episodes.first.showTitle, 'Pažvelk į profesiją kitaip');
      expect(episodes.first.seasonNumber, isNull);
    });

    test('a feed cut at 100 recordings is not numbered by date', () async {
      final episodes = await lrtProviderOver(LrtFakeSite()).children(lrtRef('zinios/2023'));
      expect(episodes, hasLength(100));
      expect(episodes.every((e) => e.episodeNumber == null), isTrue);
      expect(episodes.first.airDate!.isBefore(episodes.last.airDate!), isTrue);
      expect(episodes.first.seasonNumber, 2);
    });

    test('lengths from the programme page fill the feed recordings', () async {
      final episodes = await lrtProviderOver(LrtFakeSite()).children(lrtRef('zinios/2026'));
      expect(episodes.firstWhere((e) => e.ref.nativeId == 'rec:2000901019').durationSeconds, 820);
      expect(episodes.firstWhere((e) => e.ref.nativeId == 'rec:2000901017').durationSeconds, 642);
      expect(episodes.map((e) => e.durationSeconds), everyElement(isNotNull));
    });

    test('a recording has no children', () async {
      expect(await lrtProviderOver(LrtFakeSite()).children(lrtRecording('2000901016')), isEmpty);
    });
  });

  group('LrtProvider titles', () {
    test('a show page gives the programme with its picture', () async {
      final show = (await lrtProviderOver(LrtFakeSite()).title(lrtRef('zinios')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Žinios');
      expect(show.childCount, 6);
      expect(show.posterUrl, 'https://www.lrt.lt/img/2025/06/09/2094718-346385-{WxH}.jpg');
    });

    test('a season is found by its id', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final season = (await provider.title(lrtRef('zinios/2025')))!;
      expect(season.kind, ReplayKind.season);
      expect(season.seasonNumber, 5);
      expect(await provider.title(lrtRef('zinios/1999')), isNull);
    });

    test('a recording knows its programme, season and length', () async {
      final episode = (await lrtProviderOver(LrtFakeSite()).title(lrtRecording('2000901016')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, lrtRef('zinios'));
      expect(episode.seasonRef, lrtRef('zinios/2026'));
      expect(episode.durationSeconds, 796);
      expect(episode.summary, isNot(contains('<')));
      expect(episode.availability, ReplayAvailability.playable);
    });

    test('a missing recording is null, not an error', () async {
      expect(await lrtProviderOver(LrtFakeSite()).title(lrtRecording('2000000009')), isNull);
    });

    test('a recording whose rights ended is marked expired', () async {
      final site = LrtFakeSite()
        ..overrides['/rest-api/articles/mediateka/2000901016/x'] = (_) => LrtFakeSite.json(
          lrtFixture('article.json').replaceAll('"validTill": null', '"validTill": "2020-01-01T00:00:00.000Z"'),
        );
      final episode = (await lrtProviderOver(site).title(lrtRecording('2000901016')))!;
      expect(episode.availability, ReplayAvailability.expired);
      expect(episode.availableUntil, DateTime.utc(2020));
    });

    test('images are ours and sized on request', () {
      final provider = lrtProviderOver(LrtFakeSite());
      const template = 'https://www.lrt.lt/img/2026/10/22/2518147-674788-{WxH}.jpg';
      expect(provider.ownsImage(template), isTrue);
      expect(provider.ownsImage('https://static.arte.tv/x.jpg'), isFalse);
      expect(provider.imageUrl(template, width: 600), endsWith('-615x345.jpg'));
    });
  });
}
