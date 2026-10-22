import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/france24/france24_api.dart';
import 'package:plezy/replay/providers/france24/france24_ids.dart';
import 'package:plezy/replay/providers/france24/france24_numbering.dart';
import 'package:plezy/replay/providers/france24/france24_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'france24_recorded_api.dart';

const _source = 'france24en';
const _sports = 'WBMZ419679-F24-EN-20250402';
const _accessAsia = 'WB5600162-F24-EN-20150330';
const _meloni = 'WBMZ570142-F24-EN-20260722';
const _uuidEdition = '233B6CE2-E811-42AF-AD65-7025C02677F7';
const _uuidToken = '$_uuidEdition@20261021';
const _clip = '4220298E-F117-4CA9-B186-09222BA8DA39';

/// After every recorded rights window has opened.
final _now = DateTime.utc(2026, 10, 22, 12);

ReplayRef _ref(String id) => ReplayRef(_source, id);

RecordedFrance24 _server() => RecordedFrance24(tree: RecordedTree.english);

France24Provider _provider([RecordedFrance24? server]) => providerOver(server ?? _server(), now: _now);

void main() {
  group('France 24 English browsing', () {
    test('the source is the English edition with its own id', () {
      final source = providerOver(_server()).source;
      expect(source.id, 'france24en');
      expect(source.name, 'France 24 English');
      expect(source.language, 'en');
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 24);
    });

    test('the sections are named in English', () async {
      final categories = await providerOver(_server()).categories();
      expect(categories.map((c) => c.id), ['emissions', 'videos']);
      expect(categories.map((c) => c.title), ['Shows', 'Videos']);
    });

    test('home has English rails and only refs of this source', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.id), ['videos', 'latest', 'programmes']);
      expect(rails.map((r) => r.title), ['Latest videos', 'Latest editions', 'All shows']);
      expect([for (final r in rails) ...r.titles].every((t) => t.ref.source == _source), isTrue);
      expect(rails[0].titles, hasLength(3));
      expect(rails[1].titles, hasLength(4));
      expect(rails[2].titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('a clip of the English feed carries its length and date', () async {
      final clip = (await _provider().home())[0].titles.first;
      expect(clip.ref, _ref('v/$_clip'));
      expect(clip.kind, ReplayKind.clip);
      expect(clip.durationSeconds, 712);
      expect(clip.airDate, DateTime.utc(2026, 10, 21, 21, 21, 46));
      expect(clip.availableUntil, isNull);
      expect(clip.availability, ReplayAvailability.playable);
    });

    test('a latest edition is an episode of its show and year', () async {
      final episode = (await _provider().home())[1].titles.first;
      expect(episode.ref, _ref('$_sports/e/WBMZ595848-F24-EN-20261022'));
      expect(episode.showRef, _ref(_sports));
      expect(episode.showTitle, 'Sports');
      expect(episode.seasonRef, _ref('$_sports/2026'));
      expect(episode.seasonNumber, 2026);
      expect(episode.episodeNumber, 295);
      expect(episode.durationSeconds, 307);
      expect(episode.genres, contains('Sport'));
      expect(episode.summary, isNot(contains('<')));
    });

    test('an edition without a timestamp is dated by its id', () async {
      final episode = (await _provider().home())[1].titles[2];
      expect(episode.title, startsWith('Trump admin'));
      expect(episode.airDate, DateTime.utc(2026, 10, 22));
      expect(episode.episodeNumber, 295);
    });

    test('the video category is the English feed', () async {
      final rails = await _provider().category('videos');
      expect(rails.single.title, 'Latest videos');
      expect(rails.single.titles, hasLength(3));
      final listing = await _provider().listing('videos');
      expect(listing.totalCount, 62776);
    });

    test('a show has square and wide English artwork', () async {
      final show = (await _provider().title(_ref(_accessAsia)))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Access Asia');
      expect(show.posterUrl, contains('EN-ACCESS-ASIA_1-1-1.jpg'));
      expect(show.backdropUrl, contains('EN-ACCESS-ASIA_16-9-4K-1.jpg'));
      expect(show.summary, startsWith('Exclusive reports'));
    });
  });

  group('France 24 English The Observers', () {
    test('the YouTube-only show is left out of every list', () async {
      final provider = _provider();
      final rails = await provider.home();
      final category = await provider.category('emissions');
      final listing = await provider.listing(replayAllBrowseId);
      for (final titles in [rails[2].titles, category.single.titles, listing.titles]) {
        expect(titles, hasLength(9));
        expect(titles.map((t) => t.title), isNot(contains('The Observers')));
      }
      expect(listing.totalCount, 9);
    });

    test('it cannot be found by search or opened', () async {
      final provider = _provider();
      expect(await provider.search('observers'), isEmpty);
      expect(await provider.title(_ref(observers)), isNull);
      expect(await provider.children(_ref(observers)), isEmpty);
    });

    test('its edition with an empty file address does not play', () async {
      final provider = _provider();
      const edition = '$observers/e/WBMZ593985-F24-EN-20261015';
      expect(await provider.title(_ref(edition)), isNull);
      final playback = await provider.playback(_ref(edition));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, isNotEmpty);
    });

    test('an edition whose only file address is empty is not an episode', () async {
      final edition = editionOn(factOrFake, DateTime.utc(2026, 7, 22), 0, base: 'english/editions');
      final video = (edition['main_video'] as List).first as Map<String, dynamic>;
      video['formats'] = [
        {'code': 'MP4', 'url': ''},
      ];
      final server = _server()..histories[factOrFake] = [edition];
      expect(await _provider(server).children(_ref(factOrFake)), isEmpty);
      expect(await _provider(server).children(_ref('$factOrFake/2026')), isEmpty);
    });

    test('later pages stay full when a show is hidden from the list', () async {
      final template = fixture('english/programmes')['result']['list'][0] as Map<String, dynamic>;
      Map<String, dynamic> programme(int i, String nid) => {...template, 'nid': nid, 'title': 'Show ${100 + i}'};
      final list = [for (var i = 0; i < 30; i++) programme(i, i == 3 ? observers : 'WBMZ$i-F24-EN-20240101')];
      final provider = _provider(_server()..programmeList = list);
      final first = await provider.listing(replayAllBrowseId);
      final second = await provider.listing(replayAllBrowseId, page: 1);
      expect(first.titles, hasLength(24));
      expect(second.titles, hasLength(5));
      expect(first.totalCount, 29);
      expect({
        for (final t in [...first.titles, ...second.titles]) t.ref,
      }, hasLength(29));
      expect((await provider.listing(replayAllBrowseId, page: 2)).titles, isEmpty);
    });
  });

  group('France 24 English search', () {
    test('words match show titles regardless of case', () async {
      final provider = _provider();
      expect((await provider.search('the DEBATE')).single.title, 'The Debate');
      expect((await provider.search('truth')).single.title, 'Truth or Fake');
      expect((await provider.search('a propos')).single.title, 'A propos');
      expect((await provider.search('talking europe')).single.ref, _ref('WB4897049-F24-EN-20091009'));
    });

    test('a nonsense or blank query finds nothing', () async {
      final provider = _provider();
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
    });
  });

  group('France 24 English seasons and episodes', () {
    test('a show has one season per year of its editions', () async {
      final seasons = await _provider().children(_ref(factOrFake));
      expect(seasons.map((s) => s.title), ['2026']);
      expect(seasons.single.ref, _ref('$factOrFake/2026'));
      expect(seasons.single.showTitle, 'Fact or Fake');
    });

    test('a season lists its editions in broadcast order with day numbers', () async {
      final episodes = await _provider().children(_ref('$factOrFake/2026'));
      expect(episodes.map((e) => e.title), [
        'Maia Sandu and the European Union: the shadow of Russian disinformation',
        "Giorgia Meloni: The face of Europe's far right?",
        "Meloni's Italy: Fortress Europe?",
      ]);
      expect(episodes.map((e) => e.episodeNumber), [187, 203, 203]);
      expect(episodes.map((e) => e.durationSeconds), [142, 215, 252]);
      expect(episodes.every((e) => e.seasonNumber == 2026 && e.ref.source == _source), isTrue);
      expect(episodes.last.ref, _ref('$factOrFake/e/$_meloni'));
    });

    test('an edition is found by id with its numbers', () async {
      final episode = (await _provider().title(_ref('$factOrFake/e/$_meloni')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, _ref(factOrFake));
      expect(episode.seasonRef, _ref('$factOrFake/2026'));
      expect(episode.episodeNumber, 203);
    });

    test('a season is found by its id and an absent year is not', () async {
      final provider = _provider();
      expect((await provider.title(_ref('$factOrFake/2026')))!.seasonNumber, 2026);
      expect(await provider.title(_ref('$factOrFake/1999')), isNull);
    });
  });

  group('France 24 English editions with a UUID id', () {
    test('the day is appended to the id of an edition that has none', () async {
      final episodes = await _provider().children(_ref('$business/2026'));
      expect(episodes, hasLength(5));
      expect(episodes.map((e) => e.ref.nativeId), [
        '$business/e/WBMZ595087-F24-EN-20261019',
        '$business/e/118AEB2F-14FA-4C9D-A9E5-FF2816DC5DA9@20261020',
        '$business/e/WBMZ595404-F24-EN-20261020',
        '$business/e/80D62BEB-B60D-4642-B831-EF26DA2E459D@20261021',
        '$business/e/$_uuidToken',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [292, 293, 293, 294, 294]);
    });

    test('such an edition opens and plays from its id', () async {
      final provider = _provider();
      final episode = (await provider.title(_ref('$business/e/$_uuidToken')))!;
      expect(episode.title, 'French bond yields hit 24-year high after unrest');
      expect(episode.seasonNumber, 2026);
      expect(episode.episodeNumber, 294);
      final playback = await provider.playback(_ref('$business/e/$_uuidToken'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.label, '1080p');
    });

    test('the bare UUID has no day and cannot be found', () async {
      final provider = _provider();
      expect(await provider.title(_ref('$business/e/$_uuidEdition')), isNull);
      expect((await provider.playback(_ref('$business/e/$_uuidEdition'))).availability, ReplayAvailability.expired);
    });

    test('the same UUID with a wrong day is not found', () async {
      expect(await _provider().title(_ref('$business/e/$_uuidEdition@20250101')), isNull);
    });

    test('edition tokens keep dated ids and append a day to the others', () {
      final day = DateTime.utc(2026, 10, 21);
      expect(france24EditionToken('WBMZ1-F24-EN-20261020', day), 'WBMZ1-F24-EN-20261020');
      expect(france24EditionToken(_uuidEdition, day), _uuidToken);
    });

    test('a token splits back into the id and the day', () {
      expect(france24ParseEditionToken(_uuidToken), (nid: _uuidEdition, day: DateTime.utc(2026, 10, 21)));
      expect(france24ParseEditionToken('WBMZ1-F24-EN-20261020'), (
        nid: 'WBMZ1-F24-EN-20261020',
        day: DateTime.utc(2026, 10, 20),
      ));
      expect(france24ParseEditionToken(_uuidEdition).day, isNull);
      expect(france24ParseEditionToken('$_uuidEdition@20261340').day, isNull);
      expect(france24ParseEditionToken('$_uuidEdition@2026').day, isNull);
    });

    test('an episode id with a day survives a round trip', () {
      final native = '$business/e/$_uuidToken';
      expect(France24Id.tryParse(native)?.toString(), native);
      expect(France24Id.tryParse(native)!.refIn(_source), _ref(native));
    });
  });

  group('France 24 English playback', () {
    test('a clip offers its files from best to worst', () async {
      final playback = await _provider().playback(_ref('v/$_clip'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['1080p', '720p', '576p']);
      expect(playback.streams.first.url.toString(), endsWith('EN_20261021_223119_224312_CS_8000.mp4'));
      expect(playback.streams.last.url.toString(), endsWith('EN_20261021_223119_224312_CS.mp4'));
      expect(playback.streams.every((s) => s.url.host == 'vod-france24.akamaized.net'), isTrue);
    });

    test('an edition plays its distinct files', () async {
      final playback = await _provider().playback(_ref('$factOrFake/e/$_meloni'));
      expect(playback.streams.map((s) => s.label), ['1080p', '720p', '576p']);
      expect(playback.streams.first.url.path, endsWith('WB200460-O-01-20260723_8000.mp4'));
    });

    test('a video past its rights window is expired', () async {
      final playback = await providerOver(_server(), now: DateTime.utc(2200)).playback(_ref('v/$_clip'));
      expect(playback.availability, ReplayAvailability.expired);
      expect(playback.streams, isEmpty);
    });

    test('a video before its rights window is upcoming', () async {
      final playback = await providerOver(_server(), now: DateTime.utc(2026, 10, 20)).playback(_ref('v/$_clip'));
      expect(playback.availability, ReplayAvailability.upcoming);
    });

    test('a clip the feed no longer lists is expired', () async {
      final playback = await _provider().playback(_ref('v/00000000-0000-0000-0000-000000000000'));
      expect(playback.availability, ReplayAvailability.expired);
    });
  });

  group('France 24 English editions in the root document', () {
    test('artwork is owned and resized like the French edition', () async {
      final provider = _provider();
      const poster =
          'https://s.france24.com/media/display/4e644dfe-f0c5-11ee-acc4-005056bfb2b6/EN-ACCESS-ASIA_1-1-1.jpg';
      expect(provider.ownsImage(poster), isTrue);
      expect(
        provider.imageUrl(poster, width: 300, height: 450),
        'https://s.france24.com/media/display/4e644dfe-f0c5-11ee-acc4-005056bfb2b6/w:320/p:2x3/EN-ACCESS-ASIA_1-1-1.jpg',
      );
    });

    test('a French API over a root that lists only English reports a layout change', () async {
      final server = _server();
      final client = MediaServerHttpClient(client: MockClient((r) async => server.handle(r)));
      final api = France24Api(client, minGap: Duration.zero);
      await expectLater(api.videos(), throwsA(isA<France24LayoutChangedException>()));
    });

    test('the English tree is read through its own addresses', () async {
      final server = _server();
      await _provider(server).home();
      final paths = server.requests.map((u) => u.pathSegments.last).toSet();
      expect(paths, containsAll([RecordedTree.english.videosId, RecordedTree.english.latestId]));
      expect(paths, isNot(contains(videosGuid)));
    });
  });
}
