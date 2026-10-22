import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'aljazeera_fake_site.dart';
import 'aljazeera_playback_cases.dart';
import 'aljazeera_season_cases.dart';
import 'aljazeera_unit_cases.dart';

ReplayRef _ref(String id) => ReplayRef('aljazeera', id);

void main() {
  defineUnitCases();
  defineSeasonCases();
  definePlaybackCases();

  group('AljazeeraProvider browsing', () {
    test('the source plays clear streams in English', () {
      final source = providerOver(FakeAljazeera()).source;
      expect(source.id, 'aljazeera');
      expect(source.language, 'en');
      expect(source.support, ReplayPlaybackSupport.clear);
    });

    test('home has latest episodes, news clips and programme rows', () async {
      final rails = await providerOver(FakeAljazeera()).home();
      expect(rails.map((r) => r.id), ['inside-story', 'newsfeed', 'tv-shows', 'documentary']);
      expect(rails.first.moreBrowseId, 'p:inside-story');
      expect(rails.every((r) => r.titles.isNotEmpty), isTrue);
      expect(rails.expand((r) => r.titles).every((t) => t.ref.source == 'aljazeera'), isTrue);
    });

    test('latest episodes carry their programme, season and length', () async {
      final rails = await providerOver(FakeAljazeera()).home();
      final episode = rails.first.titles.first;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.ref, _ref('inside-story/e/6407140246112'));
      expect(episode.showRef, _ref('inside-story'));
      expect(episode.showTitle, 'Inside Story');
      expect(episode.seasonRef, _ref('inside-story/2026'));
      expect(episode.durationSeconds, 27 * 60 + 45);
      expect(episode.airDate, DateTime.utc(2026, 10, 20, 18, 45, 23));
    });

    test('news clips belong to no programme', () async {
      final rails = await providerOver(FakeAljazeera()).home();
      final clips = rails.firstWhere((r) => r.id == 'newsfeed').titles;
      expect(clips, hasLength(3));
      expect(clips.every((c) => c.kind == ReplayKind.clip && c.showRef == null), isTrue);
      expect(clips.first.ref, _ref('v/6407214258112'));
      expect(clips.first.summary, isNull);
    });

    test('a programme with no posts leaves no empty row', () async {
      final site = FakeAljazeera()..posts.remove('inside-story');
      final rails = await providerOver(site).home();
      expect(rails.map((r) => r.id), ['newsfeed', 'tv-shows', 'documentary']);
    });

    test('categories are the two sections and the news feed', () async {
      final categories = await providerOver(FakeAljazeera()).categories();
      expect(categories.map((c) => c.id), ['tv-shows', 'documentary', 'newsfeed']);
    });

    test('a section page lists its programmes as shows', () async {
      final rails = await providerOver(FakeAljazeera()).category('documentary');
      final shows = rails.single.titles;
      expect(shows.map((s) => s.title).first, 'Witness');
      expect(shows.every((s) => s.kind == ReplayKind.show), isTrue);
      expect(shows.first.genres, ['Documentary']);
      expect(await providerOver(FakeAljazeera()).category('unknown'), isEmpty);
    });

    test('the whole catalogue lists every programme once', () async {
      final page = await providerOver(FakeAljazeera()).listing(replayAllBrowseId);
      expect(page.totalCount, 12);
      expect(page.titles.map((t) => t.ref).toSet(), hasLength(12));
      expect((await providerOver(FakeAljazeera()).listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a programme listed in both sections appears once', () async {
      final site = FakeAljazeera();
      site.extraProgrammes['documentary'] = [(aljazeeraFixture('programs_tv_shows')['data'] as Map)['programs'][1]];
      final page = await providerOver(site).listing(replayAllBrowseId);
      expect(page.totalCount, 12);
      expect(page.titles.where((t) => t.title == 'Inside Story'), hasLength(1));
    });

    test('a programme feed pages by offset and keeps paging while full', () async {
      final site = FakeAljazeera()..posts['inside-story'] = postHistory('inside-story', DateTime.utc(2026, 10, 20), 30);
      final provider = providerOver(site);
      final first = await provider.listing('p:inside-story');
      expect(first.titles, hasLength(24));
      expect(first.totalCount, 25);
      final second = await provider.listing('p:inside-story', page: 1);
      expect(second.titles, hasLength(6));
      expect(second.totalCount, 30);
    });

    test('the news feed is a listing of clips', () async {
      final page = await providerOver(FakeAljazeera()).listing('newsfeed');
      expect(page.titles.every((t) => t.kind == ReplayKind.clip), isTrue);
      expect(page.totalCount, 3);
    });

    test('episodes that exist only on YouTube are never offered', () async {
      final site = FakeAljazeera();
      expect((await providerOver(site).listing('p:witness')).titles, isEmpty);
      site.posts['witness'] = [episodePost('witness', 90, DateTime.utc(2026, 10, 20)), ...site.posts['witness']!];
      final titles = (await providerOver(site).listing('p:witness')).titles;
      expect(titles.map((t) => t.ref), [_ref('witness/e/990')]);
    });
  });

  group('AljazeeraProvider search', () {
    test('programmes are found by every word, ignoring accents and case', () async {
      final provider = providerOver(FakeAljazeera());
      expect((await provider.search('TALK al jazeera')).map((t) => t.title), ['Talk to Al Jazeera']);
      expect((await provider.search('lets focus')).map((t) => t.title), ['Let’s Focus']);
      expect((await provider.search('LET’S')).map((t) => t.title), ['Let’s Focus']);
    });

    test('an empty or unmatched query returns nothing', () async {
      final provider = providerOver(FakeAljazeera());
      expect(await provider.search('  '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('episodes already listed can be found by title', () async {
      final provider = providerOver(FakeAljazeera());
      await provider.home();
      final hits = await provider.search('humanitarian crisis');
      expect(hits.map((t) => t.ref), [_ref('inside-story/e/6407140246112')]);
    });
  });

  group('AljazeeraProvider titles', () {
    test('a programme page is the show with its picture', () async {
      final show = await providerOver(FakeAljazeera()).title(_ref('inside-story'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Inside Story');
      expect(show.backdropUrl, startsWith('https://www.aljazeera.com/wp-content/uploads/'));
      expect(show.summary, contains('dissect'));
    });

    test('an episode opened by id is described by its video record', () async {
      final episode = await providerOver(FakeAljazeera()).title(_ref('inside-story/e/$recordedVideo'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.title, 'Can a humanitarian crisis in Gaza be averted?');
      expect(episode.showRef, _ref('inside-story'));
      expect(episode.showTitle, 'Inside Story');
      expect(episode.seasonRef, _ref('inside-story/2026'));
      expect(episode.durationSeconds, 1665);
      expect(episode.backdropUrl, startsWith('https://cf-images.eu-west-1.prod.boltdns.net/'));
    });

    test('a clip opened by id has no programme', () async {
      final clip = await providerOver(FakeAljazeera()).title(_ref('v/$recordedVideo'));
      expect(clip!.kind, ReplayKind.clip);
      expect(clip.showRef, isNull);
    });

    test('unknown programmes, removed videos and bad ids are not titles', () async {
      final provider = providerOver(FakeAljazeera());
      expect(await provider.title(_ref('no-such-programme')), isNull);
      expect(await provider.title(_ref('inside-story/e/1')), isNull);
      expect(await provider.title(_ref('inside-story/e/')), isNull);
      expect(await provider.title(_ref('a/b/c/d')), isNull);
    });

    test('episodes and clips have no children', () async {
      final provider = providerOver(FakeAljazeera());
      expect(await provider.children(_ref('inside-story/e/$recordedVideo')), isEmpty);
      expect(await provider.children(_ref('v/$recordedVideo')), isEmpty);
    });
  });

  group('AljazeeraApi requests', () {
    test('every catalogue call names the site and identifies the app', () async {
      final site = FakeAljazeera();
      await providerOver(site).home();
      final calls = site.requests.where((r) => r.url.path == '/graphql');
      expect(calls, isNotEmpty);
      expect(calls.every((r) => r.headers['wp-site'] == 'aje'), isTrue);
      expect(
        calls.every((r) => r.headers['User-Agent'] == 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'),
        isTrue,
      );
    });

    test('lists are cached, so a second home page costs no request', () async {
      final site = FakeAljazeera();
      final provider = providerOver(site);
      await provider.home();
      final count = site.requests.length;
      await provider.home();
      expect(site.requests.length, count);
    });

    test('a server error is raised, not mistaken for an empty list', () async {
      final site = FakeAljazeera()..status = 500;
      await expectLater(providerOver(site).home(), throwsA(anything));
    });
  });
}
