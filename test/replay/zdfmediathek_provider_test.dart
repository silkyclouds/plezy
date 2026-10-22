import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_dates.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_geo.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_images.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_mapper.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_numbering.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_text.dart';

import 'zdfmediathek_test_support.dart';

ReplayRef _ref(String id) => ReplayRef('zdfmediathek', id);

const _bergretter = 'die-bergretter-104';

void main() {
  late ZdfFakeSite site;

  setUp(() => site = ZdfFakeSite());

  group('browsing', () {
    test('home keeps the stage and the rows that hold titles', () async {
      final rails = await site.provider().home();
      expect(rails.first.id, 'stage');
      expect(rails.map((r) => r.title), contains('Doku-Reihen'));
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.id);
        expect(rail.titles.every((t) => t.ref.source == 'zdfmediathek'), isTrue);
      }
    });

    test('categories come from the overview, without the A to Z tile', () async {
      final categories = await site.provider().categories();
      expect(categories, hasLength(10));
      expect(categories.map((c) => c.id), containsAll(['serien-100', 'filme-104']));
      expect(categories.map((c) => c.id), isNot(contains('sendungen-100')));
    });

    test('a category page maps brands to shows and skips filled-later rows', () async {
      final rails = await site.provider().category('serien-100');
      expect(rails.map((r) => r.title), isNot(contains('Beliebte Serien')));
      final titles = [for (final r in rails) ...r.titles];
      expect(titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(titles.map((t) => t.title), contains('Bupkis'));
    });

    test('the whole catalogue is the A to Z list of shows', () async {
      final provider = site.provider();
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 12);
      expect(first.titles.first.title, 'Ab 18!');
      expect(first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(first.titles.map((t) => t.ref.nativeId), contains(startsWith('collection-index-page-ard')));
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('search puts shows first and reads the numbers of the videos', () async {
      final hits = await site.provider().search('tagesschau');
      expect(hits.first.kind, ReplayKind.show);
      final video = hits.firstWhere((t) => t.kind == ReplayKind.episode);
      expect(video.seasonNumber, 2026);
      expect(video.episodeNumber, 1987);
      expect(video.showTitle, 'tagesschau');
      expect(site.requestsTo('search'), 2);
    });

    test('a blank search asks nothing and an unknown one finds nothing', () async {
      final provider = site.provider();
      expect(await provider.search('   '), isEmpty);
      expect(site.requests, isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });
  });

  group('shows, seasons and episodes', () {
    test('a series lists the seasons that hold episodes', () async {
      final seasons = await site.provider().children(_ref(_bergretter));
      expect(seasons.map((s) => s.seasonNumber), [14, 15, 16, 17]);
      expect(seasons.map((s) => s.title), ['Staffel 14', 'Staffel 15', 'Staffel 16', 'Staffel 17']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref(_bergretter)), isTrue);
      expect(seasons.map((s) => s.childCount), [3, 3, 3, 3]);
      expect(seasons.first.ref, _ref('$_bergretter/14'));
    });

    test('extras of another show and trailers are not episodes', () async {
      final provider = site.provider();
      final seasons = await provider.children(_ref(_bergretter));
      final titles = [for (final season in seasons) ...(await provider.children(season.ref)).map((e) => e.title)];
      expect(titles, isNot(contains('Dreharbeiten am Limit')));
      expect(titles.where((t) => t.startsWith('Trailer')), isEmpty);
      expect(seasons.map((s) => s.seasonNumber), isNot(contains(0)));
    });

    test('a season lists its episodes with numbers and parents', () async {
      final provider = site.provider();
      final season = (await provider.children(_ref(_bergretter))).last;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.title), ['Stille Wasser', 'Ohne Ausweg', 'Lippenbekenntnisse']);
      expect(episodes.map((e) => e.episodeNumber), [1, 3, 4]);
      final first = episodes.first;
      expect(first.kind, ReplayKind.episode);
      expect(first.seasonNumber, 17);
      expect(first.seasonRef, season.ref);
      expect(first.showRef, _ref(_bergretter));
      expect(first.showTitle, 'Die Bergretter');
      expect(first.durationSeconds, 5286);
      expect(first.year, 2025);
      expect(first.airDate, DateTime.utc(2025, 10, 24, 8));
      expect(first.availableUntil, DateTime.utc(2027, 10, 21, 21, 59));
    });

    test('two parts sharing an episode number stay in order', () async {
      final provider = site.provider();
      final season = (await provider.children(_ref(_bergretter)))[1];
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.title), ['Unter Verdacht (1)', 'Unter Verdacht (2)', 'Bruderliebe (1)']);
      expect(episodes.map((e) => e.episodeNumber), [1, 1, 2]);
    });

    test('a daily news show is grouped by year with day-of-year numbers', () async {
      final provider = site.provider();
      final seasons = await provider.children(_ref('heute-journal-104'));
      expect(seasons, hasLength(1));
      expect(seasons.single.seasonNumber, 2026);
      expect(seasons.single.title, '2026');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.title), [
        'heute journal vom 19. Oktober 2026',
        'heute journal vom 20. Oktober 2026',
        'heute journal vom 21. Oktober 2026',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [292, 293, 294]);
      expect(episodes.every((e) => e.seasonRef == seasons.single.ref && e.seasonNumber == 2026), isTrue);
    });

    test('a show with nothing to number by gets one synthetic season', () async {
      site.documents['magazin-100'] = zdfBrandPage('magazin-100', 'Magazin', {
        'Neu': [
          zdfEpisodeTeaser('b-100', 'Beitrag B', brandId: 'magazin-100', extra: {'visibleFrom': '02.03.2026 10:00'}),
          zdfEpisodeTeaser('a-100', 'Beitrag A', brandId: 'magazin-100', extra: {'visibleFrom': '01.03.2026 10:00'}),
        ],
      });
      final provider = site.provider();
      final seasons = await provider.children(_ref('magazin-100'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('magazin-100/_all'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Magazin');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.title), ['Beitrag A', 'Beitrag B']);
      expect(episodes.every((e) => e.episodeNumber == null && e.seasonNumber == 1), isTrue);
    });

    test('numbers missing from the fields are read from titles and rows', () async {
      site.documents['serie-100'] = zdfBrandPage('serie-100', 'Serie', {
        'Staffel 2 - alle Folgen': [
          zdfEpisodeTeaser('s2-3', 'Folge 3: Das Ende', brandId: 'serie-100'),
          zdfEpisodeTeaser(
            's2-1',
            'Der Anfang',
            brandId: 'serie-100',
            extra: {
              'infoline': {'title': 'S2 F01 · 44 min'},
            },
          ),
        ],
        'Sonderfolgen': [zdfEpisodeTeaser('x-1', 'Ohne Nummer', brandId: 'serie-100')],
      });
      final provider = site.provider();
      final seasons = await provider.children(_ref('serie-100'));
      expect(seasons.map((s) => s.seasonNumber), [0, 2]);
      expect(seasons.first.title, 'Weitere Folgen');
      final second = await provider.children(seasons.last.ref);
      expect(second.map((e) => (e.title, e.episodeNumber)), [('Der Anfang', 1), ('Folge 3: Das Ende', 3)]);
    });

    test('an episode page knows its show and season from the show listing', () async {
      final teaser = (zdfFixture('brand_with_seasons')['cluster'] as List)[1]['teaser'][0] as Map<String, dynamic>;
      site.documents['stille-wasser-120'] = {'document': teaser};
      final episode = await site.provider().title(_ref('stille-wasser-120'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref(_bergretter));
      expect(episode.seasonRef, _ref('$_bergretter/17'));
      expect(episode.episodeNumber, 1);
    });

    test('an episode page of an unreadable show keeps its own numbers', () async {
      final episode = await site.provider().title(_ref('verzeihen-102'));
      expect(episode!.showRef, _ref('einfach-elli-100'));
      expect(episode.seasonRef, _ref('einfach-elli-100/1'));
      expect((episode.seasonNumber, episode.episodeNumber), (1, 2));
      expect(episode.summary, startsWith('Bei einem Bergrennen'));
      expect(episode.contentRating, isNull);
    });

    test('shows and seasons resolve to titles and unknown ids to null', () async {
      final provider = site.provider();
      final show = await provider.title(_ref(_bergretter));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Die Bergretter');
      expect(show.summary, startsWith('Markus Kofler'));
      expect(show.genres, ['Serien']);
      final season = await provider.title(_ref('$_bergretter/15'));
      expect(season!.kind, ReplayKind.season);
      expect(season.seasonNumber, 15);
      expect(await provider.title(_ref('missing-100')), isNull);
      expect(await provider.children(_ref('missing-100')), isEmpty);
      expect(await provider.children(_ref('verzeihen-102')), isEmpty);
    });

    test('season refs survive a round trip', () {
      final ref = ReplayRef.tryParse('zdfmediathek:$_bergretter/17');
      expect(ref, _ref('$_bergretter/17'));
    });
  });

  group('playback', () {
    test('a clear episode yields HLS, the described copy and subtitles', () async {
      final playback = await site.provider().playback(_ref('verzeihen-102'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['Deutsch', 'Audiodeskription']);
      expect(playback.streams.first.url.host, 'zdfvod.akamaized.net');
      expect(playback.streams.first.url.path, contains('/mp4/none/'));
      expect(playback.subtitles.single.url.path, endsWith('.vtt'));
      expect(playback.subtitles.single.languageCode, 'de');
      expect(site.streamRequests, 0);
    });

    test('country-flagged videos are blocked where the CDN says 403', () async {
      final provider = site.provider();
      final dach = await provider.playback(_ref('nordkoreas-geheimnisse-100'));
      expect(dach.availability, ReplayAvailability.geoBlocked);
      expect(dach.message, contains('Deutschland, Österreich, Schweiz'));
      final germany = await provider.playback(_ref('jagd-auf-virus-x-droht-die-naechste-pandemie-100'));
      expect(germany.availability, ReplayAvailability.geoBlocked);
      expect(germany.streams, isEmpty);
    });

    test('country-flagged videos play where the CDN allows them', () async {
      site.insideDach = true;
      final playback = await site.provider().playback(_ref('nordkoreas-geheimnisse-100'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.url.path, contains('/dach/'));
      expect(site.streamRequests, 1);
    });

    test('an age-checked video without streams is a time-slot restriction', () async {
      final playback = await site.provider().playback(_ref('freies-land-116'));
      expect(playback.availability, ReplayAvailability.timeSlotRestricted);
      expect(playback.message, contains('von 22 bis 6 Uhr'));
    });

    test('a video past its end is expired and one not yet online is upcoming', () async {
      site.documents['old-100'] = zdfEditedDocument('video_document_clear', (d) {
        d['offlineAvailability'] = '2026-10-01T00:00:00.000+02:00';
      });
      site.documents['soon-100'] = zdfEditedDocument('video_document_clear', (d) {
        d['formitaeten'] = [];
        d['visibleFrom'] = '25.10.2026 10:00';
      });
      final provider = site.provider();
      expect((await provider.playback(_ref('old-100'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('soon-100'))).availability, ReplayAvailability.upcoming);
    });

    test('without HLS the best progressive MP4 is offered', () async {
      site.documents['mp4-100'] = zdfEditedDocument('video_document_clear', (d) {
        d['formitaeten'] = [
          for (final f in d['formitaeten'] as List)
            if ((f as Map)['type'] == 'h264_aac_mp4_http_na_na') f,
        ];
      });
      final playback = await site.provider().playback(_ref('mp4-100'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.url.host, 'nrodlzdf-a.akamaihd.net');
    });

    test('a missing video is expired and a show is not playable', () async {
      final provider = site.provider();
      expect((await provider.playback(_ref('missing-100'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref(_bergretter))).isPlayable, isFalse);
      expect((await provider.playback(_ref('$_bergretter/17'))).isPlayable, isFalse);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await site.provider().playback(_ref('busy-100'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('every request carries an identifiable agent', () async {
      final provider = site.provider();
      await provider.home();
      await provider.playback(_ref('nordkoreas-geheimnisse-100'));
      expect(site.userAgents, isNotEmpty);
      expect(site.userAgents.every((a) => a.startsWith('Plezy-Replay (+https://github.com/')), isTrue);
    });
  });

  group('availability forecast', () {
    Future<List<ReplayTitle>> homeTitles(ReplayProvider provider) async => [
      for (final rail in await provider.home()) ...rail.titles,
    ];

    test('a viewer outside the DACH area gets restricted videos greyed', () async {
      final provider = site.provider();
      final titles = await homeTitles(provider);
      final verdicts = await (provider as ReplayAvailabilityPredictor).predictAvailability(titles, 'BE');
      expect(verdicts, {_ref('jagd-auf-virus-x-droht-die-naechste-pandemie-100'): ReplayAvailability.geoBlocked});
      expect(site.requests.where((u) => u.path.contains('document/')), isEmpty);
    });

    test('Germany sees everything, Austria and Switzerland miss Germany-only', () async {
      final provider = site.provider();
      final titles = await homeTitles(provider);
      final predictor = provider as ReplayAvailabilityPredictor;
      expect(await predictor.predictAvailability(titles, 'DE'), isEmpty);
      expect((await predictor.predictAvailability(titles, 'at')).keys, hasLength(1));
      expect((await predictor.predictAvailability(titles, 'CH')).keys, hasLength(1));
    });

    test('titles never listed are judged from their document', () async {
      final predictor = site.provider() as ReplayAvailabilityPredictor;
      final unlisted = ReplayTitle(ref: _ref('nordkoreas-geheimnisse-100'), kind: ReplayKind.episode, title: 'x');
      expect(await predictor.predictAvailability([unlisted], 'BE'), {unlisted.ref: ReplayAvailability.geoBlocked});
      expect(await predictor.predictAvailability([unlisted], 'CH'), isEmpty);
      expect(site.requestsTo('nordkoreas'), 1);
    });

    test('a title ZDF cannot be asked about stays unjudged', () async {
      final predictor = site.provider() as ReplayAvailabilityPredictor;
      final gone = ReplayTitle(ref: _ref('missing-100'), kind: ReplayKind.movie, title: 'x');
      final show = ReplayTitle(ref: _ref(_bergretter), kind: ReplayKind.show, title: 'y');
      expect(await predictor.predictAvailability([gone, show], 'BE'), isEmpty);
    });

    test('flags map to the countries they are cleared in', () {
      expect(zdfBlockedIn('none', 'BE'), isFalse);
      expect(zdfBlockedIn('dach', 'AT'), isFalse);
      expect(zdfBlockedIn('dach', 'FR'), isTrue);
      expect(zdfBlockedIn('de', 'CH'), isTrue);
      expect(zdfBlockedIn('ebu', 'BE'), isFalse);
      expect(zdfBlockedIn(null, 'BE'), isFalse);
    });
  });

  group('artwork', () {
    test('crops are picked by their real shape, not by their key', () {
      final map = {
        '1280': {'url': 'https://www.zdf.de/assets/a~1280x960', 'width': 1280, 'height': 960},
        '1920': {'url': 'https://www.zdf.de/assets/a~1920x1080', 'width': 1920, 'height': 1080},
        '1152': {'url': 'https://www.zdf.de/assets/a~1152x1296', 'width': 1152, 'height': 1296},
        '225': {'url': 'https://www.zdf.de/assets/a~225x400', 'width': 225, 'height': 400},
        '640': {'url': 'https://www.zdf.de/assets/a~640x720', 'width': 640, 'height': 720},
      };
      expect(zdfPickImage([map], ZdfPicture.backdrop), endsWith('~1920x1080'));
      expect(zdfPickImage([map], ZdfPicture.poster), endsWith('~640x720'));
    });

    test('a teaser with banners only still gets the nearest backdrop', () async {
      final show = await site.provider().title(_ref(_bergretter));
      expect(show!.backdropUrl, contains('~1200x480'));
      expect(show.posterUrl, contains('~1152x1296'));
      expect(show.logoUrl, contains('~314x314'));
    });

    test('resizing touches only 16:9 crops of known families', () async {
      final provider = site.provider();
      const wide = 'https://www.zdf.de/assets/x-100~1920x1080?cb=1';
      expect(provider.imageUrl(wide, width: 700), 'https://www.zdf.de/assets/x-100~768x432?cb=1');
      expect(provider.imageUrl(wide, width: 1300), 'https://www.zdf.de/assets/x-100~2400x1350?cb=1');
      expect(provider.imageUrl(wide), wide);
      const portrait = 'https://www.zdf.de/assets/x-100~1152x1296?cb=1';
      expect(provider.imageUrl(portrait, width: 300), portrait);
      const epg = 'https://epg-image.zdf.de/fotobase-webdelivery/images/id?layout=1920x1080';
      expect(provider.imageUrl(epg, width: 300), endsWith('layout=384x216'));
      expect(provider.imageUrl('https://example.com/a.jpg', width: 300), 'https://example.com/a.jpg');
    });

    test('only ZDF image hosts are claimed', () {
      final provider = site.provider();
      expect(provider.ownsImage('https://www.zdf.de/assets/x~1x1'), isTrue);
      expect(provider.ownsImage('https://epg-image.zdf.de/a?layout=1x1'), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
    });
  });

  group('dates and numbers', () {
    test('Berlin winter and summer time convert to UTC', () {
      expect(zdfLocalDate('05.03.2026 10:00'), DateTime.utc(2026, 3, 5, 9));
      expect(zdfLocalDate('21.10.2026 15:25'), DateTime.utc(2026, 10, 21, 13, 25));
      expect(zdfLocalDate('25.10.2026 03:30'), DateTime.utc(2026, 10, 25, 2, 30));
      expect(zdfLocalDate('26.10.2026 12:00'), DateTime.utc(2026, 10, 26, 11));
      expect(zdfLocalDate('29.03.2026 03:00'), DateTime.utc(2026, 3, 29, 1));
      expect(zdfLocalDate('16.03.2026'), DateTime.utc(2026, 3, 15, 23));
      expect(zdfLocalDate('31.02.2026 10:00'), isNull);
      expect(zdfLocalDate('soon'), isNull);
    });

    test('a calendar day is read from a title in either notation', () {
      expect(zdfTitleDate('heute journal vom 21. Oktober 2026'), DateTime.utc(2026, 10, 21));
      expect(zdfTitleDate('tagesschau 20:00 Uhr, 21.10.2026'), DateTime.utc(2026, 10, 21));
      expect(zdfTitleDate('Couchsurfen vom 19. März 2026'), DateTime.utc(2026, 3, 19));
      expect(zdfTitleDate('Folge 12'), isNull);
      expect(zdfTitleDate('am 31.02.2026'), isNull);
      expect(zdfDayOfYear(DateTime.utc(2026, 10, 21)), 294);
    });

    test('numbers come from fields, the info line, the title, then the row', () {
      expect(zdfNumbers({'seasonNumber': '01', 'episodeNumber': '02'}), (season: 1, episode: 2));
      expect(zdfNumbers({'seasonNumber': '2026', 'episodeNumber': '0'}), (season: 2026, episode: null));
      expect(
        zdfNumbers({
          'infoline': {'title': 'S2026 F17 · 43 min'},
        }),
        (season: 2026, episode: 17),
      );
      expect(zdfNumbers({'titel': 'Neues aus dem Dorf - Folge 4'}, clusterName: 'Staffel 3 - alle'), (
        season: 3,
        episode: 4,
      ));
      expect(zdfNumbers({'titel': '5. Folge'}), (season: null, episode: 5));
      expect(zdfNumbers({'titel': 'Trailer zur 18. Bergretter-Staffel'}), (season: null, episode: null));
      expect(zdfNumbers({'titel': '2. Staffel: Rückkehr'}), (season: 2, episode: null));
    });

    test('invisible marks are removed from descriptions', () {
      final marks = String.fromCharCodes([0x200e, 0x200f]);
      expect(zdfText('${marks}Geschichten $marks'), 'Geschichten');
      expect(zdfText('  '), isNull);
    });
  });

  group('mapping', () {
    ZdfMapper mapper() => ZdfMapper(ZdfGeoLedger(), clock: () => zdfNow);

    test('live channels, categories and links out are not titles', () {
      expect(mapper().title({'id': 'a', 'type': 'livevideo'}), isNull);
      expect(mapper().title({'id': 'a', 'type': 'category'}), isNull);
      expect(mapper().title({'id': 'a', 'type': 'video', 'contentType': 'live', 'currentVideoType': 'live'}), isNull);
      expect(mapper().title({'type': 'video', 'titel': 'no id'}), isNull);
    });

    test('a film has no show, a clip is a clip, a teaser carries its rating', () {
      final film = mapper().title(zdfEpisodeTeaser('film-100', 'Ein Film', extra: {'fsk': 'fsk12'}));
      expect(film!.kind, ReplayKind.movie);
      expect(film.showRef, isNull);
      expect(film.contentRating, '12+');
      final clip = mapper().title(zdfEpisodeTeaser('clip-100', 'Ein Beitrag', extra: {'contentType': 'clip'}));
      expect(clip!.kind, ReplayKind.clip);
    });

    test('a teaser past its end is expired and one not online is upcoming', () {
      final past = mapper().title(
        zdfEpisodeTeaser('p', 'x', extra: {'offlineAvailability': '2026-10-01T00:00:00.000+02:00'}),
      );
      final future = mapper().title(zdfEpisodeTeaser('f', 'x', extra: {'visibleFrom': '30.10.2026 10:00'}));
      expect(past!.availability, ReplayAvailability.expired);
      expect(future!.availability, ReplayAvailability.upcoming);
    });
  });
}
