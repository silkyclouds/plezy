import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'rtveplay_test_support.dart';
import 'rtveplay_unit_cases.dart';

http.Response _jsonOk(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('RtvePlayProvider browsing', () {
    test('the menu is the channels, newest videos first', () async {
      final categories = await RtveFakeSite().provider().categories();
      expect(categories.first.id, 'latest');
      expect(categories.map((c) => c.title), containsAll(['La 1', 'La 2', 'Clan']));
    });

    test('home has newest episodes, channel rows and new programmes', () async {
      final rails = await RtveFakeSite().provider().home();
      expect(rails.map((r) => r.id), [
        'latest',
        'new-la1',
        'new-la2',
        'new-clan',
        'new-teledeporte',
        'new-archivo-rtve',
        'new-programs',
      ]);
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.id);
        expect(rail.titles.every((t) => t.ref.source == 'rtveplay'), isTrue);
      }
    });

    test('a radio podcast shows in the newest row but not in channel rows', () async {
      final rails = await RtveFakeSite().provider().home();
      expect(rails.first.titles.map((t) => t.showTitle), contains('Guinda y guindilla'));
      final channelRows = rails.where((r) => r.id.startsWith('new-') && r.id != 'new-programs');
      expect(channelRows.expand((r) => r.titles).map((t) => t.showTitle), isNot(contains('Guinda y guindilla')));
    });

    test('a programme with several new videos appears once per row', () async {
      final site = RtveFakeSite();
      final first = rtveItemsOf('videos_latest').first;
      final sibling = rtveEdited(first, (c) {
        c['id'] = '99000001';
        c['title'] = 'Another edition';
        c['shortTitle'] = 'Another edition';
      });
      site.overrides['/api/videos.json'] = (_) => _jsonOk(rtvePage([first, sibling]));
      final rails = await site.provider().home();
      expect(rails.first.titles, hasLength(1));
    });

    test('new programmes carry resizable poster and backdrop references', () async {
      final rails = await RtveFakeSite().provider().home();
      final shows = rails.firstWhere((r) => r.id == 'new-programs').titles;
      expect(shows.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(shows.first.posterUrl, 'https://img.rtve.es/p/1031439?imgProgApi=imgPoster');
      expect(shows.first.backdropUrl, 'https://img.rtve.es/p/1031439?imgProgApi=imgPortada');
    });

    test('a channel page groups its programmes by type', () async {
      final rails = await RtveFakeSite().provider().category('748');
      expect(rails.first.id, 'new');
      final byTitle = {for (final r in rails) r.title: r};
      expect(byTitle.keys, containsAll(['Concursos', 'Serie Documental', 'Series Prime Time']));
      final documentaries = byTitle['Serie Documental']!.titles.map((t) => t.title);
      expect(documentaries, contains('Amparo Muñoz. La mujer que dijo no'));
    });

    test('programmes left out of the site A-Z are hidden', () async {
      final rails = await RtveFakeSite().provider().category('748');
      final titles = [for (final r in rails) ...r.titles.map((t) => t.title)];
      expect(titles, isNot(contains('Abba. Contra todo pronóstico')));
    });

    test('an unknown category is empty', () async {
      expect(await RtveFakeSite().provider().category('nope'), isEmpty);
    });

    test('the latest category lists episodes, not programmes', () async {
      final rails = await RtveFakeSite().provider().category('latest');
      expect(rails.first.id, 'latest');
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.episode), isTrue);
    });

    test('the whole catalogue lists television programmes of the A-Z', () async {
      final site = RtveFakeSite();
      final shows = rtveItemsOf('programas_page');
      final radio = rtveEdited(shows.first, (c) {
        c['id'] = '9001';
        c['channel'] = {'uid': 'CRN_RADIO3', 'title': 'Radio 3'};
      });
      final hidden = rtveEdited(shows.first, (c) {
        c['id'] = '9002';
        c['inAZList'] = false;
      });
      site.overrides['/api/programas.json'] = (_) => _jsonOk(rtvePage([...shows, radio, hidden], total: 4638));
      final page = await site.provider().listing(replayAllBrowseId);
      expect(page.titles.map((t) => t.ref.nativeId), ['p1031439', 'p1031448']);
      expect(page.totalCount, 4638);
    });

    test('a listing page asks for the matching page of the API', () async {
      final site = RtveFakeSite();
      await site.provider().listing('748', page: 2);
      final request = site.to('/api/cadenas/748/programas.json').single;
      expect(request.url.queryParameters['page'], '3');
      expect(request.url.queryParameters['size'], '50');
    });

    test('the latest listing slices the two reachable API pages', () async {
      final site = RtveFakeSite();
      final template = rtveItemsOf('videos_latest').first;
      List<Map<String, dynamic>> hundred(int from) => [
        for (var i = 0; i < 100; i++) rtveEdited(template, (c) => c['id'] = '${from + i}'),
      ];
      site.overrides['/api/videos.json'] = (r) =>
          _jsonOk(rtvePage(hundred(r.url.queryParameters['page'] == '1' ? 1000 : 2000), total: 440414));
      final provider = site.provider();
      final second = await provider.listing('latest', page: 1);
      expect(second.titles.first.ref.nativeId, 'v1050');
      expect(second.titles, hasLength(50));
      expect(second.totalCount, 200);
      expect((await provider.listing('latest', page: 2)).titles.first.ref.nativeId, 'v2000');
      expect((await provider.listing('latest', page: 4)).titles, isEmpty);
    });

    test('search lists programmes first, then episodes, without repeats', () async {
      final provider = RtveFakeSite().provider();
      final results = await provider.search('cuentame');
      final kinds = results.map((t) => t.kind).toList();
      expect(kinds.first, ReplayKind.show);
      expect(kinds.skipWhile((k) => k == ReplayKind.show).every((k) => k != ReplayKind.show), isTrue);
      expect(results.map((t) => t.ref).toSet(), hasLength(results.length));
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('   '), isEmpty);
    });

    test('a search hit keeps the numbers RTVE states', () async {
      final results = await RtveFakeSite().provider().search('cuentame');
      final tale = results.firstWhere((t) => t.title == 'Cuéntame un cuento');
      expect(tale.episodeNumber, 5);
      expect(tale.showTitle, 'Aprendemos en Clan');
      expect(tale.durationSeconds, 1764);
    });
  });

  group('RtvePlayProvider shows', () {
    test('a show lists its seasons in order with episode counts', () async {
      final seasons = await RtveFakeSite().provider().children(rtveRef('p175650'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      expect(seasons.map((s) => s.childCount), [226, 500, 40]);
      expect(seasons.first.ref, rtveRef('p175650/1000630'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == rtveRef('p175650')), isTrue);
      expect(seasons.first.title, 'Temporada 1');
    });

    test('a season lists episodes numbered from their titles, in order', () async {
      final provider = RtveFakeSite().provider();
      final episodes = await provider.children(rtveRef('p175650/1000630'));
      expect(episodes.map((e) => e.episodeNumber), [231, 232]);
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.seasonNumber == 1), isTrue);
      expect(episodes.first.seasonRef, rtveRef('p175650/1000630'));
      expect(episodes.first.showTitle, 'Mañaneros 360');
    });

    test('a long season is read page by page', () async {
      final site = RtveFakeSite();
      final firstPage = rtveItemsOf('temporada_videos');
      final secondPage = [for (final (i, item) in firstPage.indexed) rtveEdited(item, (c) => c['id'] = '${88000 + i}')];
      site.overrides['/temporadas/1000630/videos'] = (r) =>
          _jsonOk(rtvePage(r.url.queryParameters['page'] == '1' ? firstPage : secondPage, totalPages: 2));
      final episodes = await site.provider().children(rtveRef('p175650/1000630'));
      expect(episodes, hasLength(4));
      expect(site.to('/temporadas/1000630/videos').map((r) => r.url.queryParameters['type']).toSet(), {'39816'});
    });

    test('a programme without seasons has one synthetic season', () async {
      final provider = RtveFakeSite().provider();
      final seasons = await provider.children(rtveRef('p117610'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, rtveRef('p117610/_all'));
      expect(seasons.single.seasonNumber, 1);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [535, 536, 537, 538, 539, 540]);
      expect(episodes.first.title, 'Programa 535');
    });

    test('dated editions without numbers keep the order RTVE gives', () async {
      final site = RtveFakeSite();
      final evening = rtveItemsOf('videos_latest').firstWhere((v) => v['title'].toString().startsWith('Telediario'));
      final editions = [
        evening,
        rtveEdited(evening, (c) {
          c['id'] = '99000002';
          c['title'] = c['shortTitle'] = 'Telediario - 15 horas - 21/10/26';
        }),
        rtveEdited(evening, (c) {
          c['id'] = '99000003';
          c['title'] = c['shortTitle'] = 'Telediario - 21 horas - 20/10/26';
        }),
      ];
      site.overrides['/api/programas/117610/videos'] = (_) => _jsonOk(rtvePage(editions));
      final episodes = await site.provider().children(rtveRef('p117610/_all'));
      expect(episodes.map((e) => e.ref.nativeId), ['v${evening['id']}', 'v99000002', 'v99000003']);
      expect(episodes.every((e) => e.episodeNumber == null && e.airDate != null), isTrue);
    });

    test('a show with seasons can also list every episode at once', () async {
      final episodes = await RtveFakeSite().provider().children(rtveRef('p1573/_all'));
      expect(episodes, isNotEmpty);
      expect(episodes.map((e) => e.episodeNumber), containsAll([6, 7, 8]));
      expect(episodes.first.seasonNumber, 23);
    });

    test('a programme that does not exist has no children', () async {
      final provider = RtveFakeSite().provider();
      expect(await provider.children(rtveRef('p42')), isEmpty);
      expect(await provider.children(rtveRef('p42/_all')), isEmpty);
      expect(await provider.children(rtveRef('v16177116')), isEmpty);
    });

    test('a show title reads the programme record', () async {
      final show = (await RtveFakeSite().provider().title(rtveRef('p175650')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Mañaneros 360');
      expect(show.childCount, 3);
      expect(show.genres, ['Información y actualidad']);
      expect(show.logoUrl, 'https://img.rtve.es/p/175650?imgProgApi=logo');
      expect(show.summary, isNot(contains('<')));
    });

    test('a season title is found among its show seasons', () async {
      final season = (await RtveFakeSite().provider().title(rtveRef('p175650/1000631')))!;
      expect(season.seasonNumber, 2);
      expect(season.childCount, 500);
    });

    test('an episode page knows its show, season, numbers and dates', () async {
      final episode = (await RtveFakeSite().provider().title(rtveRef('v16177116')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, rtveRef('p111570'));
      expect(episode.seasonRef, rtveRef('p111570/_all'));
      expect(episode.showTitle, 'Saber vivir');
      expect(episode.summary, contains('por qué buscamos'));
      expect(episode.summary, isNot(contains('&')));
      expect(episode.durationSeconds, 2163);
      expect(episode.airDate, DateTime.utc(2024, 7, 7, 8, 25));
      expect(episode.contentRating, 'TP');
      expect(episode.posterUrl, 'https://img.rtve.es/v/16177116');
    });

    test('a licensed episode keeps its season and number', () async {
      final episode = (await RtveFakeSite().provider().title(rtveRef('v1888987')))!;
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 33);
      expect(episode.seasonRef, rtveRef('p1573/40034'));
      expect(episode.directors, hasLength(4));
      expect(episode.cast.first, 'Ana Duato');
      expect(episode.contentRating, '12+');
    });

    test('missing and foreign ids resolve to nothing', () async {
      final provider = RtveFakeSite().provider();
      expect(await provider.title(rtveRef('p99999999')), isNull);
      expect(await provider.title(rtveRef('v1')), isNull);
      expect(await provider.title(rtveRef('123')), isNull);
    });
  });

  group('RtvePlayProvider playback', () {
    test('a free video yields its HLS master and every subtitle track', () async {
      final playback = await RtveFakeSite().provider().playback(rtveRef('v16177116'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'rtvehlsvodlote7.rtve.es');
      expect(playback.streams.single.url.path, endsWith('/video.m3u8'));
      expect(playback.subtitles.map((s) => s.languageCode), ['es', 'en', 'gl', 'ca', 'eu']);
      expect(playback.subtitles.first.label, 'Español');
      expect(playback.subtitles.first.url.path, endsWith('.vtt'));
    });

    test('a country refusal is reported as geoblocked with the country', () async {
      final playback = await RtveFakeSite().provider().playback(rtveRef('v16859989'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('BE'));
      expect(playback.streams, isEmpty);
    });

    test('a refusal without a country is geoblocked and mentions the account', () async {
      final playback = await RtveFakeSite().provider().playback(rtveRef('v1888987'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('account'));
    });

    test('a refused video past its end date is reported as expired', () async {
      final site = RtveFakeSite();
      final record = rtveEdited(
        rtveItemsOf('video_item_pasarela_403').single,
        (c) => c['expirationDate'] = '01-01-2020 00:00:00',
      );
      site.overrides['/api/videos/1888987.json'] = (_) => _jsonOk(rtvePage([record]));
      expect((await site.provider().playback(rtveRef('v1888987'))).availability, ReplayAvailability.expired);
    });

    test('a refused video withdrawn by RTVE is reported as expired', () async {
      final site = RtveFakeSite();
      final record = rtveEdited(
        rtveItemsOf('video_item_pasarela_403').single,
        (c) => c['pubState'] = {'code': 'DESPU'},
      );
      site.overrides['/api/videos/1888987.json'] = (_) => _jsonOk(rtvePage([record]));
      expect((await site.provider().playback(rtveRef('v1888987'))).availability, ReplayAvailability.expired);
    });

    test('a refused video not yet published is reported as upcoming', () async {
      final site = RtveFakeSite();
      final record = rtveEdited(rtveItemsOf('video_item_pasarela_403').single, (c) {
        c['publicationDateTimestamp'] = DateTime.utc(2027).millisecondsSinceEpoch;
      });
      site.overrides['/api/videos/1888987.json'] = (_) => _jsonOk(rtvePage([record]));
      expect((await site.provider().playback(rtveRef('v1888987'))).availability, ReplayAvailability.upcoming);
    });

    test('a refusal stays geoblocked when the catalogue is unreachable', () async {
      final site = RtveFakeSite();
      site.overrides['/api/videos/16859989.json'] = (_) => http.Response('boom', 500);
      expect((await site.provider().playback(rtveRef('v16859989'))).availability, ReplayAvailability.geoBlocked);
    });

    test('an encrypted playlist is reported as DRM protected', () async {
      final site = RtveFakeSite();
      site.overrides['/video.m3u8'] = (_) => http.Response(
        '#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://key"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8',
        200,
      );
      final playback = await site.provider().playback(rtveRef('v16177116'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a manifest that is gone is reported as expired', () async {
      final site = RtveFakeSite();
      site.overrides['/video.m3u8'] = (_) => http.Response('', 404);
      expect((await site.provider().playback(rtveRef('v16177116'))).availability, ReplayAvailability.expired);
    });

    test('an unknown video is reported as expired, not as an error', () async {
      expect((await RtveFakeSite().provider().playback(rtveRef('v5'))).availability, ReplayAvailability.expired);
    });

    test('an unexpected manifest status says what RTVE answered', () async {
      final site = RtveFakeSite();
      site.overrides['/video.m3u8'] = (_) => http.Response('', 502);
      final playback = await site.provider().playback(rtveRef('v16177116'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('502'));
    });

    test('rate limiting is reported without throwing', () async {
      final site = RtveFakeSite();
      site.overrides['/16177116.png'] = (_) => http.Response('', 429, headers: {'retry-after': '30'});
      final playback = await site.provider().playback(rtveRef('v16177116'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('missing subtitles do not stop playback', () async {
      final site = RtveFakeSite();
      site.overrides['/subtitulos.json'] = (_) => http.Response('boom', 500);
      final playback = await site.provider().playback(rtveRef('v16177116'));
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles, isEmpty);
    });

    test('a show or a season is never played directly', () async {
      final provider = RtveFakeSite().provider();
      expect((await provider.playback(rtveRef('p175650'))).isPlayable, isFalse);
      expect((await provider.playback(rtveRef('p175650/1000630'))).isPlayable, isFalse);
    });

    test('every request names the app and sends no credentials', () async {
      final site = RtveFakeSite();
      final provider = site.provider();
      await provider.playback(rtveRef('v16177116'));
      await provider.search('cuentame');
      expect(site.requests, isNotEmpty);
      for (final request in site.requests) {
        expect(request.headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
        expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
        expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
      }
    });

    test('catalogue documents are cached between calls', () async {
      final site = RtveFakeSite();
      final provider = site.provider();
      await provider.title(rtveRef('p175650'));
      await provider.children(rtveRef('p175650'));
      expect(site.to('/api/programas/175650.json'), hasLength(1));
    });
  });

  defineRtveUnitCases();
}
