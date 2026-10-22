import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ted/ted_api.dart';
import 'package:plezy/replay/providers/ted/ted_ids.dart';
import 'package:plezy/replay/providers/ted/ted_images.dart';
import 'package:plezy/replay/providers/ted/ted_playback.dart';
import 'package:plezy/replay/providers/ted/ted_provider.dart';

import 'ted_fixture_server.dart';

ReplayRef _talk(String slug) => tedTalkRef(slug);

const _candace = 'candace_parker_how_to_break_down_barriers_and_not_accept_limits';
const _aiPlaylist = 'talks_on_ai_and_the_future_of_work';

void main() {
  late TedFixtureServer server;
  late TedProvider provider;

  setUp(() {
    server = TedFixtureServer();
    provider = server.provider();
  });

  group('TedProvider browsing', () {
    test('the source is a clear English catalogue', () {
      expect(provider.source.id, 'ted');
      expect(provider.source.language, 'en');
      expect(provider.source.support, ReplayPlaybackSupport.clear);
    });

    test('home lists the latest talks first, then playlists, then topics', () async {
      final rails = await provider.home();
      expect(rails.first.id, 'latest');
      expect(rails[1].id, 'playlists');
      expect(rails.map((r) => r.id), contains('topic/science'));
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.id);
        expect(rail.titles.every((t) => t.ref.source == 'ted'), isTrue);
      }
      expect(rails.first.moreBrowseId, replayAllBrowseId);
    });

    test('the whole catalogue is the talks, newest first, with the real total', () async {
      final page = await provider.listing(replayAllBrowseId);
      expect(page.totalCount, 5286);
      expect(page.titles.first.kind, ReplayKind.movie);
      expect(page.titles.first.title, 'Want someone to change? Ask this question');
    });

    test('a later page asks for the matching offset', () async {
      final page = await provider.listing(replayAllBrowseId, page: 1);
      expect(server.queries.single, contains('after: "20"'));
      expect(page.titles.first.ref, _talk('zach_deboer_why_we_should_design_cities_like_disney'));
    });

    test('a topic lists its talks', () async {
      final page = await provider.listing('topic/science');
      expect(page.totalCount, 1737);
      expect(page.titles, hasLength(3));
    });

    test('playlists list as shows', () async {
      final page = await provider.listing('playlists');
      expect(page.totalCount, 771);
      expect(page.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(page.titles.first.ref, tedPlaylistRef('ted_talks_on_critical_thinking_and_philosophy'));
    });

    test('an unknown listing is empty rather than an error', () async {
      final page = await provider.listing('nowhere');
      expect(page.titles, isEmpty);
      expect(page.totalCount, 0);
    });

    test('categories offer the latest talks, playlists and topics', () async {
      final categories = await provider.categories();
      expect(categories.map((c) => c.id).take(3), [replayAllBrowseId, 'playlists', 'topic/technology']);
    });

    test('a category page is one row that opens the full listing', () async {
      final rails = await provider.category('topic/science');
      expect(rails.single.title, 'Science');
      expect(rails.single.moreBrowseId, 'topic/science');
      expect(await provider.category('topic'), isEmpty);
    });

    test('a language asks for talks translated into it', () async {
      final french = server.provider(language: 'fr');
      final page = await french.listing(replayAllBrowseId);
      expect(server.queries.single, contains('language: "fr"'));
      expect(page.titles.first.title, startsWith('Et si vous pouviez'));
    });

    test('English is the original language and sends no filter', () async {
      await server.provider(language: 'en').listing(replayAllBrowseId);
      expect(server.queries.single, isNot(contains('language')));
    });

    test('repeating a request inside the cache window does not reach TED', () async {
      await provider.listing(replayAllBrowseId);
      await provider.listing(replayAllBrowseId);
      expect(server.queries, hasLength(1));
    });
  });

  group('TedProvider search', () {
    test('results come back as talks in the order TED ranked them', () async {
      final talks = await provider.search('climate');
      expect(talks.map((t) => t.title).first, 'What happens to the plastic you throw away?');
      expect(talks, hasLength(4));
      expect(talks.every((t) => t.kind == ReplayKind.movie && t.posterUrl != null), isTrue);
      expect(server.queries, hasLength(2));
    });

    test('a blank query and a query without hits return nothing', () async {
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('an answer without data is reported as an API error', () async {
      expect(provider.search('broken'), throwsA(isA<TedApiException>()));
    });
  });

  group('TedProvider talks', () {
    test('a talk is a movie with presenter, year, topics and artwork', () async {
      final talk = (await provider.title(_talk(_candace)))!;
      expect(talk.kind, ReplayKind.movie);
      expect(talk.title, 'How to break down barriers and not accept limits');
      expect(talk.subtitle, 'Candace Parker');
      expect(talk.cast, ['Candace Parker']);
      expect(talk.durationSeconds, 679);
      expect(talk.year, 2021);
      expect(talk.airDate, DateTime.utc(2022, 1, 14, 15, 39, 45));
      expect(talk.genres, containsAll(['Personal growth', 'Social change', 'Sports']));
      expect(talk.summary, startsWith('What can'));
      expect(talk.availability, ReplayAvailability.playable);
    });

    test('the poster is the stage shot and the backdrop the wide picture', () async {
      final talk = (await provider.title(_talk(_candace)))!;
      expect(talk.posterUrl, endsWith('stageshot.jpg'));
      expect(talk.backdropUrl, endsWith('embed.jpg'));
    });

    test('whitespace in titles is normalised', () async {
      final talks = await provider.search('climate');
      expect(talks.map((t) => t.title), contains('The state of the climate crisis in 2020'));
    });

    test('a talk TED no longer has is null', () async {
      expect(await provider.title(_talk('nope_not_a_talk')), isNull);
    });

    test('a talk has no children', () async {
      expect(await provider.children(_talk(_candace)), isEmpty);
    });

    test('a ref from another source or of another shape is ignored', () async {
      expect(await provider.title(const ReplayRef('arte', 'talk/x')), isNull);
      expect(await provider.title(const ReplayRef('ted', 'garbage')), isNull);
      expect(await provider.children(const ReplayRef('ted', 'garbage')), isEmpty);
    });
  });

  group('TedProvider playlists', () {
    final show = tedPlaylistRef(_aiPlaylist);

    test('a playlist is a show with its own description and pictures', () async {
      final title = (await provider.title(show))!;
      expect(title.kind, ReplayKind.show);
      expect(title.title, 'Talks on AI and the future of work');
      expect(title.summary, startsWith('Everyone has an opinion'));
      expect(title.posterUrl, contains('2000x2000'));
      expect(title.backdropUrl, contains('1200x627'));
    });

    test('a playlist has one synthetic season holding every talk', () async {
      final seasons = await provider.children(show);
      expect(seasons, hasLength(1));
      expect(seasons.single.kind, ReplayKind.season);
      expect(seasons.single.ref, tedSeasonRef(_aiPlaylist));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.childCount, 11);
      expect(seasons.single.showRef, show);
    });

    test('the season lists the talks as numbered episodes in playlist order', () async {
      final episodes = await provider.children(tedSeasonRef(_aiPlaylist));
      expect(episodes, hasLength(11));
      expect(episodes.map((e) => e.episodeNumber), [for (var i = 1; i <= 11; i++) i]);
      expect(episodes.first.title, startsWith('Will AI take your job'));
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.seasonNumber == 1), isTrue);
      expect(episodes.first.showRef, show);
      expect(episodes.first.showTitle, 'Talks on AI and the future of work');
      expect(episodes.first.seasonRef, tedSeasonRef(_aiPlaylist));
    });

    test('an episode keeps the ref of its talk, so it plays like a movie', () async {
      final episodes = await provider.children(tedSeasonRef(_aiPlaylist));
      expect(episodes.first.ref.nativeId, startsWith('talk/'));
    });

    test('a playlist longer than one request is read in pages', () async {
      final episodes = await provider.children(tedSeasonRef('long_playlist'));
      expect(episodes, hasLength(120));
      expect(episodes.map((e) => e.episodeNumber), [for (var i = 1; i <= 120; i++) i]);
      expect(server.queries.where((q) => q.contains('after:')), hasLength(2));
    });

    test('the season title carries the playlist name and the talk count', () async {
      final season = (await provider.title(tedSeasonRef(_aiPlaylist)))!;
      expect(season.title, 'Talks on AI and the future of work');
      expect(season.childCount, 11);
    });

    test('a playlist TED no longer has gives nothing', () async {
      final gone = tedPlaylistRef('gone');
      expect(await provider.title(gone), isNull);
      expect(await provider.children(gone), isEmpty);
      expect(await provider.children(tedSeasonRef('gone')), isEmpty);
      expect(await provider.title(tedSeasonRef('gone')), isNull);
    });
  });

  group('TedProvider playback', () {
    test('a talk plays its HLS master and lists every subtitle language', () async {
      final playback = await provider.playback(_talk(_candace));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'hls.ted.com');
      expect(playback.streams.single.url.path, '/project_masters/7506/manifest.m3u8');
      expect(playback.subtitles, hasLength(27));
      expect(playback.subtitles.map((s) => s.languageCode), containsAll(['en', 'fr', 'pt-br', 'zh-cn', 'zh-tw']));
    });

    test('subtitle playlists resolve against the master and keep its query', () async {
      final playback = await provider.playback(_talk(_candace));
      final french = playback.subtitles.firstWhere((s) => s.languageCode == 'fr');
      expect(french.url.toString(), 'https://hls.ted.com/project_masters/937/subtitles/fr.m3u8?intro_master_id=9294');
      expect(french.label, 'French');
      expect(french.forced, isFalse);
    });

    test('a master without the intro gives plain subtitle addresses', () async {
      final playback = await provider.playback(_talk('plain_talk'));
      expect(playback.subtitles.map((s) => s.url.toString()), [
        'https://hls.ted.com/project_masters/12091/subtitles/en.m3u8',
        'https://hls.ted.com/project_masters/12091/subtitles/ar.m3u8',
      ]);
    });

    test('a label with a comma stays whole', () async {
      final playback = await provider.playback(_talk(_candace));
      final labels = playback.subtitles.map((s) => s.label);
      expect(labels, containsAll(['Portuguese, Brazilian', 'Chinese, Simplified']));
    });

    test('a talk without a stream address is unavailable', () async {
      final playback = await provider.playback(_talk('no_stream'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('a talk TED removed is expired', () async {
      expect((await provider.playback(_talk('nope_not_a_talk'))).availability, ReplayAvailability.expired);
    });

    test('a master that is gone, forbidden or encrypted says why', () async {
      expect((await provider.playback(_talk('removed_master'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_talk('forbidden_master'))).availability, ReplayAvailability.geoBlocked);
      expect((await provider.playback(_talk('encrypted_master'))).availability, ReplayAvailability.drmProtected);
    });

    test('a page where a playlist should be is not played', () async {
      expect((await provider.playback(_talk('html_master'))).availability, ReplayAvailability.unknown);
    });

    test('a server error is not hidden as an availability', () async {
      expect(provider.playback(_talk('failing_master')), throwsA(isA<MediaServerHttpException>()));
    });

    test('playlists and seasons are never played directly', () async {
      expect((await provider.playback(tedPlaylistRef(_aiPlaylist))).isPlayable, isFalse);
      expect((await provider.playback(tedSeasonRef(_aiPlaylist))).isPlayable, isFalse);
    });

    test('lists predict nothing blocked for a talk that has a stream', () async {
      final page = await provider.listing(replayAllBrowseId);
      expect(page.titles.every((t) => t.availability == ReplayAvailability.playable), isTrue);
    });
  });

  group('TED rate limiting', () {
    test('a 429 is reported with its delay and later calls wait without asking', () async {
      var now = DateTime.utc(2026, 1, 1);
      final api = TedApi(server.client, clock: () => now);
      final limited = TedProvider.withApi(api);

      await expectLater(limited.search('429'), throwsA(isA<TedRateLimitedException>()));
      final asked = server.queries.length;
      now = now.add(const Duration(seconds: 10));
      await expectLater(limited.listing(replayAllBrowseId), throwsA(isA<TedRateLimitedException>()));
      expect(server.queries, hasLength(asked));

      now = now.add(const Duration(seconds: 30));
      expect((await limited.listing(replayAllBrowseId)).titles, isNotEmpty);
    });

    test('playback turns a 429 into a message instead of throwing', () async {
      final api = TedApi(server.client, clock: () => DateTime.utc(2026, 1, 1));
      final limited = TedProvider.withApi(api);
      await expectLater(limited.search('429'), throwsA(isA<TedRateLimitedException>()));
      final playback = await limited.playback(_talk(_candace));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('retry'));
    });
  });

  group('TED subtitles', () {
    final master = Uri.parse('https://hls.ted.com/project_masters/5/manifest.m3u8?intro_master_id=9294');

    test('only subtitle entries become tracks, audio entries do not', () {
      const text = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="medium",LANGUAGE="en",URI="a.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",LANGUAGE="de",NAME="Deutsch",FORCED=YES,URI="/s/de.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",LANGUAGE="xx",NAME="No address"
''';
      final subtitles = tedSubtitlesFromMaster(master, text);
      expect(subtitles, hasLength(1));
      expect(subtitles.single.forced, isTrue);
      expect(subtitles.single.url.path, '/s/de.m3u8');
    });

    test('a repeated address is listed once', () {
      const line = '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",LANGUAGE="de",NAME="Deutsch",URI="/s/de.m3u8"\n';
      expect(tedSubtitlesFromMaster(master, '#EXTM3U\n$line$line'), hasLength(1));
    });

    test('a master without subtitles still plays', () {
      final playback = tedPlaybackFromMaster(master, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n');
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles, isEmpty);
    });
  });

  group('TED images', () {
    const wide = 'https://pi.tedcdn.com/r/talkstar-assets.s3.amazonaws.com/production/talks/talk_1/a/x-1350x675.jpg';
    const original = 'https://pe.tedcdn.com/images/ted/abc_2880x1620.jpg';

    test('the resizer gets the wanted width', () {
      expect(tedImageUrl(wide, width: 400), '$wide?w=400');
      expect(tedImageUrl('$wide?quality=70', width: 400), '$wide?quality=70&w=400');
      expect(tedImageUrl(wide), wide);
    });

    test('widths are kept within what the pictures offer', () {
      expect(tedImageUrl(wide, width: 9000), '$wide?w=1920');
    });

    test('originals are fetched through the resizer', () {
      expect(
        tedImageUrl(original, width: 640),
        'https://pi.tedcdn.com/r/pe.tedcdn.com/images/ted/abc_2880x1620.jpg?w=640',
      );
    });

    test('only TED picture hosts are recognised', () {
      expect(provider.ownsImage(wide), isTrue);
      expect(provider.ownsImage(original), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(wide, width: 300), '$wide?w=300');
    });
  });

  group('TED refs', () {
    test('talk, playlist and season refs round trip through their string form', () {
      for (final ref in [_talk('a_b'), tedPlaylistRef('c_d'), tedSeasonRef('c_d')]) {
        expect(tedTarget(ReplayRef.tryParse(ref.toString())!), tedTarget(ref));
      }
      expect(tedTarget(tedSeasonRef('c_d'))!.kind, TedRefKind.season);
      expect(tedTarget(const ReplayRef('ted', 'playlist/x/other')), isNull);
    });
  });
}
