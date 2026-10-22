import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/dw/dw_catalog.dart';
import 'package:plezy/replay/providers/dw/dw_ids.dart';
import 'package:plezy/replay/providers/dw/dw_images.dart';
import 'package:plezy/replay/providers/dw/dw_mapper.dart';
import 'package:plezy/replay/providers/dw/dw_numbering.dart';
import 'package:plezy/replay/providers/dw/dw_provider.dart';

import 'dw_fixture_server.dart';

ReplayRef _ref(String id) => ReplayRef('dw', id);

final _docfilm = _ref('p294010');

void main() {
  late DwFixtureServer server;
  late DwProvider provider;

  setUp(() {
    server = DwFixtureServer();
    provider = server.provider();
  });

  group('DW source', () {
    test('it is an English source with clear streams', () {
      expect(provider.source.id, 'dw');
      expect(provider.source.language, 'en');
      expect(provider.source.support, ReplayPlaybackSupport.clear);
    });

    test('it offers programmes and latest videos as sections', () async {
      final categories = await provider.categories();
      expect(categories.map((c) => c.id), ['programmes', 'latest']);
    });

    test('requests announce Plezy and ask for JSON', () async {
      await provider.category('programmes');
      expect(server.requests.single.headers['User-Agent'], contains('Plezy-Replay'));
      expect(server.requests.single.headers['Accept'], 'application/json');
    });

    test('repeated reads inside the cache window hit the network once', () async {
      await provider.category('programmes');
      await provider.category('programmes');
      expect(server.requests, hasLength(1));
    });
  });

  group('DW browsing', () {
    test('home has latest videos, flagship rows and all programmes', () async {
      final rails = await provider.home();
      expect(rails.map((r) => r.id), ['latest', 'p294010', 'p262267', 'p877843', 'p66947984', 'programmes']);
      expect(rails.every((r) => r.titles.every((t) => t.ref.source == 'dw')), isTrue);
      expect(rails.last.moreBrowseId, replayAllBrowseId);
      expect(rails[1].title, 'DocFilm');
    });

    test('programmes come as shows, A to Z, with a tagline', () async {
      final rails = await provider.category('programmes');
      final shows = rails.single.titles;
      expect(shows.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(
        shows.map((s) => s.title.toLowerCase()),
        orderedEquals([...shows.map((s) => s.title.toLowerCase())]..sort()),
      );
      final euromaxx = shows.firstWhere((s) => s.title == 'Euromaxx');
      expect(euromaxx.subtitle, 'Culture. Ideas. Europe.');
      expect(euromaxx.ref, _ref('p877843'));
      expect(euromaxx.posterUrl, startsWith('https://static.dw.com/image/'));
    });

    test('latest videos mix clips and programme episodes', () async {
      final titles = (await provider.category('latest')).single.titles;
      expect(titles.map((t) => t.kind).toSet(), {ReplayKind.clip, ReplayKind.episode});
      expect(titles.every((t) => t.isPlayable), isTrue);
    });

    test('the whole catalogue is the programmes, paged by thirty', () async {
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 8);
      expect(first.titles, hasLength(8));
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('listing latest sends the page and reports the total', () async {
      final page = await provider.listing('latest', page: 2);
      expect(page.titles, isNotEmpty);
      expect(page.totalCount, greaterThan(0));
      final sent = jsonDecode(server.searches.single.body) as Map<String, dynamic>;
      expect((sent['page'] as Map)['current'], 3);
      expect((sent['page'] as Map)['size'], 30);
      expect(sent['sort'], [
        {'contentDate': 'desc'},
      ]);
    });

    test('listing a programme filters the search on its id', () async {
      final page = await provider.listing('p294010');
      expect(page.titles.every((t) => t.showRef == _docfilm), isTrue);
      expect(server.searches.single.body, contains('"unifiedPrograms.id":294010'));
    });

    test('an unknown browse id lists nothing', () async {
      expect((await provider.listing('nonsense')).titles, isEmpty);
      expect(server.requests, isEmpty);
    });

    test('the search engine window is never exceeded', () async {
      expect((await provider.listing('latest', page: 400)).titles, isEmpty);
      expect(server.requests, isEmpty);
    });
  });

  group('DW seasons and episodes', () {
    test('a show opens into one season per year with video counts', () async {
      final seasons = await provider.children(_docfilm);
      expect(seasons.first.seasonNumber, 2007);
      expect(seasons.last.seasonNumber, 2026);
      expect(seasons.last.childCount, 102);
      expect(seasons.last.title, '2026');
      expect(seasons.last.ref, _ref('p294010/2026'));
      expect(seasons.map((s) => s.seasonNumber), orderedEquals([...seasons.map((s) => s.seasonNumber!)]..sort()));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _docfilm), isTrue);
      expect(seasons.first.showTitle, 'DocFilm');
    });

    test('years without videos get no season', () async {
      final years = (await provider.children(_docfilm)).map((s) => s.seasonNumber);
      expect(years, isNot(contains(2010)));
    });

    test('a season asks for its own year only', () async {
      await provider.children(_ref('p294010/2026'));
      final sent = jsonDecode(server.searches.single.body) as Map<String, dynamic>;
      final range = ((sent['filters'] as Map)['all'] as List).last['contentDate'] as Map;
      expect(range['from'], '2026-01-01T00:00:00.000Z');
      expect(range['to'], '2027-01-01T00:00:00.000Z');
    });

    test('episodes carry the day of year as their number', () async {
      final episodes = await provider.children(_ref('p294010/2026'));
      expect(episodes, isNotEmpty);
      final first = episodes.firstWhere((e) => e.ref == _ref('78363545'));
      expect(first.kind, ReplayKind.episode);
      expect(first.seasonNumber, 2026);
      expect(first.episodeNumber, 294);
      expect(first.seasonRef, _ref('p294010/2026'));
      expect(first.showRef, _docfilm);
      expect(first.showTitle, 'DocFilm');
      expect(first.durationSeconds, 2634);
      expect(first.genres, ['Equality']);
      expect(first.title, 'Female construction workers in Germany');
    });

    test('episodes run oldest first', () async {
      final episodes = await provider.children(_ref('p294010/2026'));
      final dates = [for (final e in episodes) e.airDate!];
      expect(dates, orderedEquals([...dates]..sort()));
    });

    test('a long season keeps the newest three hundred episodes', () async {
      final episodes = await provider.children(_ref('p$dwBigProgramme/2026'));
      expect(episodes, hasLength(dwMaxEpisodesPerSeason));
      expect(episodes.last.title, 'Episode 0');
      expect(episodes.first.title, 'Episode 299');
      expect(server.searches, hasLength(3));
    });

    test('a short season pages until its last hit', () async {
      final episodes = await provider.children(_ref('p$dwSmallProgramme/2026'));
      expect(episodes, hasLength(dwSmallTotal));
      expect(server.searches, hasLength(2));
    });

    test('a season is found again from its ref', () async {
      final season = await provider.title(_ref('p294010/2024'));
      expect(season!.kind, ReplayKind.season);
      expect(season.childCount, 68);
      expect(await provider.title(_ref('p294010/1999')), isNull);
    });

    test('a programme page gives the show with its summary', () async {
      final show = await provider.title(_docfilm);
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'DocFilm');
      expect(show.summary, contains('carefully researched'));
    });

    test('an id that is not a programme is not a show', () async {
      expect(await provider.title(_ref('p78363545')), isNull);
      expect(await provider.children(_ref('p78363545')), isEmpty);
    });

    test('a video page knows its programme, season and number', () async {
      final video = await provider.title(_ref('78363545'));
      expect(video!.kind, ReplayKind.episode);
      expect(video.showRef, _docfilm);
      expect(video.seasonRef, _ref('p294010/2026'));
      expect(video.seasonNumber, 2026);
      expect(video.episodeNumber, 294);
      expect(video.summary, contains('sexism'));
    });

    test('a video without a programme is a clip with no season', () async {
      final clip = await provider.title(_ref('79610229'));
      expect(clip!.kind, ReplayKind.clip);
      expect(clip.showRef, isNull);
      expect(clip.seasonNumber, isNull);
      expect(clip.episodeNumber, isNull);
      expect(clip.durationSeconds, 1214);
      expect(await provider.children(clip.ref), isEmpty);
    });

    test('a missing or foreign video is not found', () async {
      expect(await provider.title(_ref('1111')), isNull);
      expect(await provider.title(_ref('2222')), isNull);
      expect(await provider.title(_ref('not-an-id')), isNull);
    });
  });

  group('DW search', () {
    test('matching programmes come before video hits', () async {
      final hits = await provider.search('docfilm');
      expect(hits.first.kind, ReplayKind.show);
      expect(hits.first.title, 'DocFilm');
      expect(hits.skip(1).every((t) => t.isPlayable), isTrue);
    });

    test('the text is sent as a video-only query', () async {
      final hits = await provider.search('  climate ');
      expect(hits.where((t) => t.kind == ReplayKind.show), isEmpty);
      expect(hits, isNotEmpty);
      final sent = jsonDecode(server.searches.single.body) as Map<String, dynamic>;
      expect(sent['query'], 'climate');
      expect(((sent['filters'] as Map)['all'] as List).first, {'modelType': 'VIDEO'});
      expect(sent.containsKey('sort'), isFalse);
    });

    test('no hit and a blank query both return nothing', () async {
      expect(await provider.search('qqq'), isEmpty);
      expect(await provider.search('   '), isEmpty);
    });
  });

  group('DW playback', () {
    test('a video plays its HLS master with English subtitles', () async {
      final playback = await provider.playback(_ref('79610229'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'hlsvod.dw.com');
      expect(playback.streams.single.url.path, endsWith('master.m3u8'));
      expect(playback.subtitles.single.url.toString(), 'https://www.dw.com/media/subtitles/79646538');
      expect(playback.subtitles.single.languageCode, 'en');
      expect(playback.subtitles.single.label, 'English');
    });

    test('a video without subtitles offers none', () async {
      final playback = await provider.playback(_ref('78363545'));
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles, isEmpty);
    });

    test('a removed video is reported as expired', () async {
      expect((await provider.playback(_ref('1111'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('2222'))).availability, ReplayAvailability.expired);
    });

    test('a video not yet published is upcoming', () async {
      final playback = await provider.playback(_ref('4444'));
      expect(playback.availability, ReplayAvailability.upcoming);
      expect(playback.streams, isEmpty);
    });

    test('a published video without a stream says so', () async {
      final playback = await provider.playback(_ref('3333'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('no video stream'));
    });

    test('a legal block answer is geo-blocked', () async {
      expect((await provider.playback(_ref('6666'))).availability, ReplayAvailability.geoBlocked);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await provider.playback(_ref('5555'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a programme or season is never played directly', () async {
      expect((await provider.playback(_docfilm)).isPlayable, isFalse);
      expect((await provider.playback(_ref('p294010/2026'))).isPlayable, isFalse);
      expect(server.requests, isEmpty);
    });
  });

  group('DW images', () {
    const template = r'https://static.dw.com/image/78277766_${formatId}.jpg';

    test('landscape boxes pick the smallest format that covers them', () {
      expect(dwImageUrl(template, width: 300, height: 170), endsWith('78277766_602.jpg'));
      expect(dwImageUrl(template, width: 1000, height: 560), endsWith('78277766_605.jpg'));
      expect(dwImageUrl(template, width: 5000, height: 2000), endsWith('78277766_607.jpg'));
      expect(dwImageUrl(template), endsWith('78277766_604.jpg'));
    });

    test('tall boxes use the portrait crops', () {
      expect(dwImageUrl(template, width: 300, height: 450), endsWith('78277766_701.jpg'));
      expect(dwImageUrl(template, width: 400, height: 600), endsWith('78277766_702.jpg'));
    });

    test('a reference with a fixed format is returned unchanged', () {
      const fixed = 'https://static.dw.com/image/78277766_605.jpg';
      expect(dwImageUrl(fixed, width: 300), fixed);
    });

    test('only addresses on the image host are owned', () {
      expect(provider.ownsImage(template), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(dwImageReference(r'https://example.com/a_${formatId}.jpg'), isNull);
    });

    test('titles carry the sized template for poster and backdrop', () async {
      final show = (await provider.category('programmes')).single.titles.first;
      expect(show.posterUrl, show.backdropUrl);
      expect(provider.imageUrl(show.posterUrl!, width: 300, height: 170), isNot(contains('formatId')));
    });
  });

  group('DW derivation rules', () {
    test('the day of year follows the calendar, leap years included', () {
      expect(dwDayOfYear(DateTime.utc(2026, 1, 1)), 1);
      expect(dwDayOfYear(DateTime.utc(2026, 12, 31)), 365);
      expect(dwDayOfYear(DateTime.utc(2028, 12, 31)), 366);
      expect(dwDayOfYear(DateTime.parse('2026-10-21T23:59:59-05:00')), 295);
    });

    test('a programme title splits into name and tagline', () {
      expect(dwSplitProgrammeTitle('Euromaxx — Culture. Ideas. Europe.'), (
        name: 'Euromaxx',
        tagline: 'Culture. Ideas. Europe.',
      ));
      expect(dwSplitProgrammeTitle('DW News'), (name: 'DW News', tagline: null));
      expect(dwSplitProgrammeTitle('HER - Women in Asia').name, 'HER - Women in Asia');
    });

    test('native ids tell videos, shows and seasons apart', () {
      expect(DwId.tryParse('78363545')!.isVideo, isTrue);
      expect(DwId.tryParse('p294010')!.isShow, isTrue);
      expect(DwId.tryParse('p294010/2026')!.isSeason, isTrue);
      expect(DwId.tryParse('p294010/26'), isNull);
      expect(DwId.tryParse(''), isNull);
    });

    test('a native id with a slash survives a ref round trip', () {
      final ref = ReplayRef.tryParse('dw:p294010/2026');
      expect(ref, _ref('p294010/2026'));
    });
  });
}
