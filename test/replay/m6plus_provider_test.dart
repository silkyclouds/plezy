import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'm6plus_fixture_server.dart';

ReplayRef _ref(String id) => ReplayRef('m6plus', id);

void main() {
  late M6plusFixtureServer server;
  late ReplayProvider provider;

  setUp(() {
    server = M6plusFixtureServer();
    provider = server.provider();
  });

  group('M6plusProvider browsing', () {
    test('the source is browse-only French M6+', () {
      expect(provider.source.id, 'm6plus');
      expect(provider.source.name, 'M6+');
      expect(provider.source.language, 'fr');
      expect(provider.source.support, ReplayPlaybackSupport.browseOnly);
    });

    test('categories start with the free section and list the folders', () async {
      final categories = await provider.categories();
      expect(categories.first.id, 'free');
      expect(categories.map((c) => c.id), containsAll(['8', '10', '52', '2996']));
    });

    test('home leads with new programmes, newest first', () async {
      final rails = await provider.home();
      expect(rails.first.id, 'recent');
      final titles = rails.first.titles;
      final newest = (readFixture('programs_page') as List).cast<Map<String, dynamic>>().reduce(
        (a, b) =>
            (a['last_clip_publication']['date'] as String).compareTo(b['last_clip_publication']['date']) >= 0 ? a : b,
      );
      expect(titles.first.title, newest['title']);
      expect(titles.every((t) => t.ref.source == 'm6plus'), isTrue);
    });

    test('home has a free-content row and a row per busy channel', () async {
      final rails = await provider.home();
      final free = rails.firstWhere((r) => r.id == 'free');
      expect(free.titles.every((t) => t.availability == ReplayAvailability.playable || t.childCount == null), isTrue);
      expect(rails.map((r) => r.title), contains('M6'));
      expect(rails.map((r) => r.title), isNot(contains('Gulli')));
    });

    test('a listing page is exact when the server returns a short page', () async {
      final page = await provider.listing(replayAllBrowseId);
      expect(page.titles, hasLength(14));
      expect(page.totalCount, 14);
    });

    test('a full listing page says that more may follow', () async {
      server.fullFirstPage = true;
      final page = await provider.listing(replayAllBrowseId);
      expect(page.titles, hasLength(100));
      expect(page.totalCount, 101);
    });

    test('a page past the end is empty', () async {
      final page = await provider.listing(replayAllBrowseId, page: 3);
      expect(page.titles, isEmpty);
    });

    test('a category page maps programmes and offers the whole folder', () async {
      final rails = await provider.category('8');
      expect(rails.single.titles.map((t) => t.title), contains('Top chef'));
      expect(rails.single.moreBrowseId, isNull);
      expect(await provider.category('58'), isEmpty);
    });

    test('the free section keeps only programmes with extracts or podcasts', () async {
      final page = await provider.listing('free');
      expect(page.totalCount, 7);
      final titles = page.titles.map((t) => t.title);
      expect(titles, containsAll(['Les traîtres : nouvelle génération', 'Les 1001 vies de…']));
      expect(titles, isNot(contains('Fury')));
    });

    test('a programme with nothing to watch is left out of lists', () async {
      final empty = Map<String, dynamic>.from(readFixture('program_28545') as Map)
        ..['id'] = 5
        ..['title'] = 'Vide'
        ..['count'] = {'vi': 0, 'vc': 0, 'playlist': 0, 'podcast': 0, 'audiobook': 0};
      server.extraPrograms['5'] = empty;
      final titles = (await provider.listing(replayAllBrowseId)).titles;
      expect(titles.map((t) => t.title), isNot(contains('Vide')));
    });

    test('search ignores accents and ranks title prefixes first', () async {
      expect((await provider.search('traitres')).single.ref, _ref('26360'));
      expect((await provider.search('amour pre')).single.ref, _ref('857'));
      final little = await provider.search('little');
      expect(little.map((t) => t.title), ['Pretty little liars']);
    });

    test('search finds nothing for noise or a blank query', () async {
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
    });

    test('the catalogue is fetched once for home, search and the free section', () async {
      await provider.home();
      await provider.search('top');
      await provider.listing('free');
      final pages = server.requests.where((u) => u.path.endsWith('/programs')).length;
      expect(pages, 1);
    });
  });

  group('M6plusProvider predicted availability', () {
    test('programmes with full videos are badged protected', () async {
      final titles = {for (final t in (await provider.listing(replayAllBrowseId)).titles) t.ref.nativeId: t};
      expect(titles['28545']!.availability, ReplayAvailability.drmProtected);
      expect(titles['28336']!.availability, ReplayAvailability.drmProtected);
    });

    test('podcast-only programmes are playable and premium ones need a login', () async {
      final titles = {for (final t in (await provider.listing(replayAllBrowseId)).titles) t.ref.nativeId: t};
      expect(titles['28137']!.availability, ReplayAvailability.playable);
      expect(titles['28127']!.availability, ReplayAvailability.loginRequired);
    });

    test('a single-work programme is a movie, a series stays a show', () async {
      final titles = {for (final t in (await provider.listing(replayAllBrowseId)).titles) t.ref.nativeId: t};
      expect(titles['28336']!.kind, ReplayKind.movie);
      expect(titles['28127']!.kind, ReplayKind.movie);
      expect(titles['28545']!.kind, ReplayKind.show);
      expect(titles['843']!.kind, ReplayKind.show);
    });

    test('episodes are badged protected, extracts playable, premium gated', () async {
      final episodes = await provider.children(_ref('26360/s1'));
      expect(episodes.every((e) => e.availability == ReplayAvailability.drmProtected), isTrue);
      final clips = await provider.children(_ref('26360/clips'));
      expect(clips.every((c) => c.availability == ReplayAvailability.playable), isTrue);
      final paywalled = await provider.children(_ref('20534/s1'));
      expect(paywalled, isNotEmpty);
      expect(paywalled.every((e) => e.availability == ReplayAvailability.loginRequired), isTrue);
    });
  });

  group('M6plusProvider shows', () {
    test('a series lists numbered seasons with their episode counts', () async {
      final seasons = await provider.children(_ref('28545'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      expect(seasons.map((s) => s.childCount), [2, 1, 2]);
      expect(seasons.map((s) => s.title), ['Saison 1', 'Saison 2', 'Saison 3']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('28545')), isTrue);
      expect(seasons.first.ref, _ref('28545/s1'));
    });

    test('a season lists its episodes in order with numbers and parents', () async {
      final episodes = await provider.children(_ref('28545/s3'));
      expect(episodes.map((e) => e.episodeNumber), [4, 10]);
      expect(episodes.first.title, 'La plume est dans le sac');
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonNumber, 3);
      expect(episodes.first.seasonRef, _ref('28545/s3'));
      expect(episodes.first.showRef, _ref('28545'));
      expect(episodes.first.showTitle, 'Pretty little liars');
      expect(episodes.first.durationSeconds, 2538);
      expect(episodes.first.contentRating, '-10');
    });

    test('season and episode numbers come from titles when metadata lacks them', () async {
      final seasons = await provider.children(_ref(titlesOnlyProgram));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      final season3 = await provider.children(_ref('$titlesOnlyProgram/s3'));
      expect(season3.map((e) => e.episodeNumber), [4, 10]);
      expect(season3.first.title, 'La plume est dans le sac');
    });

    test('videos without a season share one season named Épisodes', () async {
      final seasons = await provider.children(_ref('28525'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('28525/other'));
      expect(seasons.single.title, 'Épisodes');
      expect(seasons.single.seasonNumber, 1);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5]);
    });

    test('extracts get a season zero, after the numbered seasons', () async {
      final seasons = await provider.children(_ref('26360'));
      expect(seasons.map((s) => s.ref.nativeId), ['26360/s1', '26360/clips']);
      expect(seasons.last.title, 'Extraits et bonus');
      expect(seasons.last.seasonNumber, 0);
      expect(seasons.last.childCount, 4);
      final clips = await provider.children(seasons.last.ref);
      expect(clips.every((c) => c.kind == ReplayKind.clip && c.episodeNumber == null), isTrue);
    });

    test('podcasts form one season of audio clips', () async {
      final seasons = await provider.children(_ref('28137'));
      expect(seasons.single.title, 'Podcasts');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(3));
      expect(episodes.first.kind, ReplayKind.clip);
      expect(episodes.first.durationSeconds, 2511);
    });

    test('a movie has a title but no children', () async {
      final movie = await provider.title(_ref('28336'));
      expect(movie!.kind, ReplayKind.movie);
      expect(movie.title, 'Fury');
      expect(movie.year, 2014);
      expect(movie.posterUrl, startsWith('https://images-fio.6play.fr/v2/images/'));
      expect(await provider.children(_ref('28336')), isEmpty);
    });

    test('a show title carries genre, rating, summary and artwork', () async {
      final show = await provider.title(_ref('28545'));
      expect(show!.kind, ReplayKind.show);
      expect(show.genres, ['Série dramatique']);
      expect(show.contentRating, '-10');
      expect(show.summary, isNotEmpty);
      expect(show.posterUrl, endsWith('/5028359/raw'));
      expect(show.backdropUrl, endsWith('/5028354/raw'));
      expect(show.logoUrl, endsWith('/5028362/raw'));
      expect(show.availableUntil?.year, 2027);
    });

    test('an episode page knows its show and season', () async {
      final episode = await provider.title(_ref('clip_13200229'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('28545'));
      expect(episode.seasonRef, _ref('28545/s3'));
      expect(episode.seasonNumber, 3);
      expect(episode.episodeNumber, 4);
      expect(episode.backdropUrl, endsWith('/5028856/raw'));
    });

    test('a season is found from its reference', () async {
      final season = await provider.title(_ref('28545/s3'));
      expect(season!.kind, ReplayKind.season);
      expect(season.seasonNumber, 3);
      expect(await provider.title(_ref('28545/s9')), isNull);
    });

    test('a withdrawn programme or video gives nothing', () async {
      expect(await provider.title(_ref('999')), isNull);
      expect(await provider.children(_ref('999')), isEmpty);
      expect(await provider.title(_ref('clip_1')), isNull);
    });
  });

  group('M6plusProvider playback', () {
    test('a clear clip yields its HLS ladders, best first', () async {
      final playback = await provider.playback(_ref('clip_13094113'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['HD', 'SD']);
      expect(playback.streams.first.url.host, 'lbcdn.6cloud.fr');
      expect(playback.streams.first.url.path, endsWith('.m3u8'));
      expect(playback.streams.first.url.path, contains('_unp'));
    });

    test('a podcast yields its audio file without fetching it', () async {
      final playback = await provider.playback(_ref('clip_13201870'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.label, 'Audio');
      expect(playback.streams.single.url.host, 'audio.audiomeans.fr');
      expect(server.requests.where((u) => u.host == 'audio.audiomeans.fr'), isEmpty);
    });

    test('protected episodes are never offered, whatever their country', () async {
      for (final id in ['clip_13200229', 'clip_12571221']) {
        final playback = await provider.playback(_ref(id));
        expect(playback.availability, ReplayAvailability.drmProtected, reason: id);
        expect(playback.streams, isEmpty);
        expect(playback.message, contains('DRM'));
      }
      expect(server.requests.where((u) => u.host == 'lbcdn.6cloud.fr'), isEmpty);
    });

    test('a premium video needs a login', () async {
      final playback = await provider.playback(_ref('clip_13176172'));
      expect(playback.availability, ReplayAvailability.loginRequired);
    });

    test('a free video without streams is expired, or upcoming before its date', () async {
      final free = Map<String, dynamic>.from(readFixture('video_premium') as Map)
        ..['freemium_packs'] = <Object>[]
        ..['freemium_products'] = <Object>[];
      server.extraVideos['clip_gone'] = {...free, 'id': 'clip_gone'};
      server.extraVideos['clip_soon'] = {...free, 'id': 'clip_soon', 'publication_date': '2027-01-01 00:00:00'};
      expect((await provider.playback(_ref('clip_gone'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('clip_soon'))).availability, ReplayAvailability.upcoming);
    });

    test('a country outside the rights zone is reported with the allowed ones', () async {
      server.manifestBlocked = true;
      final playback = await provider.playback(_ref('clip_13094113'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('BE'));
      expect(playback.message, contains('FR'));
      expect(playback.message, isNot(contains('192.0.2.1')));
    });

    test('once the country is known, clear lists predict the block', () async {
      server.extraVideos['clip_fr'] = server.restrictedCopy('clip_13094113', ['AD', 'FR']);
      expect((await provider.title(_ref('clip_fr')))!.availability, ReplayAvailability.playable);

      server.manifestBlocked = true;
      await provider.playback(_ref('clip_13094113'));

      expect((await provider.title(_ref('clip_fr')))!.availability, ReplayAvailability.geoBlocked);
      final blocked = await provider.playback(_ref('clip_fr'));
      expect(blocked.availability, ReplayAvailability.geoBlocked);
      expect(blocked.message, allOf(contains('BE'), contains('FR')));
      expect(
        (await provider.title(_ref('clip_13094114')))?.availability ?? ReplayAvailability.playable,
        isNot(ReplayAvailability.geoBlocked),
      );
    });

    test('a manifest that is gone is reported as expired', () async {
      server.manifestStatus = 404;
      expect((await provider.playback(_ref('clip_13094113'))).availability, ReplayAvailability.expired);
      server.manifestStatus = 500;
      final failed = await provider.playback(_ref('clip_13094113'));
      expect(failed.availability, ReplayAvailability.unknown);
      expect(failed.message, contains('500'));
    });

    test('a single-work programme resolves to its only video', () async {
      expect((await provider.playback(_ref('28336'))).availability, ReplayAvailability.drmProtected);
      expect((await provider.playback(_ref('28127'))).availability, ReplayAvailability.loginRequired);
    });

    test('a show, a season or an unknown id is never played directly', () async {
      expect((await provider.playback(_ref('28545'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('28545/s3'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('clip_0'))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await provider.playback(_ref('clip_429'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('no stream offered across the fixtures is protected', () async {
      for (final id in ['clip_13094113', 'clip_13094114', 'clip_13201870', 'clip_13200229', 'clip_12571221']) {
        final playback = await provider.playback(_ref(id));
        for (final stream in playback.streams) {
          expect(stream.url.path, isNot(contains('drm')), reason: id);
          expect(stream.url.path, isNot(contains('dashcenc')), reason: id);
        }
      }
    });
  });
}
