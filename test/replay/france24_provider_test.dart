import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/france24/france24_ids.dart';
import 'package:plezy/replay/providers/france24/france24_images.dart';

import 'france24_recorded_api.dart';

ReplayRef _ref(String id) => ReplayRef('france24', id);

void _setValidity(Map<String, dynamic> feed, String nid, {int? from, int? until}) {
  final list = (feed['result'] as Map<String, dynamic>)['list'] as List;
  final video = list.cast<Map<String, dynamic>>().firstWhere((v) => v['nid'] == nid);
  if (from != null) video['validity_start_date'] = '$from';
  if (until != null) video['validity_end_date'] = '$until';
}

void main() {
  group('France24Provider browsing', () {
    test('the source is a clear French one with the API page size', () {
      final source = providerOver(RecordedFrance24()).source;
      expect(source.id, 'france24');
      expect(source.name, 'France 24');
      expect(source.language, 'fr');
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 24);
    });

    test('there are two sections, programmes and videos', () async {
      final categories = await providerOver(RecordedFrance24()).categories();
      expect(categories.map((c) => c.id), ['emissions', 'videos']);
    });

    test('home lists recent clips, latest editions and programmes', () async {
      final rails = await providerOver(RecordedFrance24()).home();
      expect(rails.map((r) => r.id), ['videos', 'latest', 'programmes']);
      expect(rails[0].titles.every((t) => t.kind == ReplayKind.clip), isTrue);
      expect(rails[1].titles.single.kind, ReplayKind.episode);
      expect(rails[2].titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(rails[0].moreBrowseId, 'videos');
      expect(rails[2].moreBrowseId, replayAllBrowseId);
      expect([for (final r in rails) ...r.titles].every((t) => t.ref.source == 'france24'), isTrue);
    });

    test('a latest edition is an episode placed in its programme and year', () async {
      final episode = (await providerOver(RecordedFrance24()).home())[1].titles.single;
      expect(episode.title, '17 octobre : le retour des courtes peines');
      expect(episode.showRef, _ref(lesCles));
      expect(episode.showTitle, "Les clés de l'info");
      expect(episode.seasonRef, _ref('$lesCles/2026'));
      expect(episode.seasonNumber, 2026);
      expect(episode.episodeNumber, 294);
      expect(episode.durationSeconds, 384);
      expect(episode.genres, contains('France'));
      expect(episode.summary, isNot(contains('<')));
    });

    test('an edition id is made of its programme and its own id', () async {
      final episode = (await providerOver(RecordedFrance24()).home())[1].titles.single;
      expect(episode.ref.nativeId, '$lesCles/e/WBMZ707277-F24-FR-20261021');
    });

    test('clips carry their label, length and open-ended rights', () async {
      final clip = (await providerOver(RecordedFrance24()).home())[0].titles.first;
      expect(clip.ref, _ref('v/$clipWithAllFormats'));
      expect(clip.subtitle, 'Analyse');
      expect(clip.durationSeconds, 287);
      expect(clip.airDate, DateTime.utc(2026, 10, 21, 6, 22, 37));
      expect(clip.availableUntil, isNull);
      expect(clip.availability, ReplayAvailability.playable);
    });

    test('the programme category lists every programme of both pages', () async {
      final rails = await providerOver(RecordedFrance24()).category('emissions');
      expect(rails.single.titles, hasLength(6));
      expect(rails.single.titles.first.title, 'ActuElles');
    });

    test('the video category is the first page of the feed', () async {
      final rails = await providerOver(RecordedFrance24()).category('videos');
      expect(rails.single.titles, hasLength(2));
      expect(await providerOver(RecordedFrance24()).category('nope'), isEmpty);
    });

    test('the full listing pages through programmes', () async {
      final provider = providerOver(RecordedFrance24());
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 47);
      expect(first.titles, hasLength(4));
      final second = await provider.listing(replayAllBrowseId, page: 1);
      expect(second.titles.map((t) => t.title), ['Le débat', 'Légendes urbaines']);
      expect((await provider.listing(replayAllBrowseId, page: 5)).titles, isEmpty);
    });

    test('the video listing and unknown listings behave', () async {
      final provider = providerOver(RecordedFrance24());
      final videos = await provider.listing('videos');
      expect(videos.titles, hasLength(2));
      expect(videos.totalCount, 62519);
      expect((await provider.listing('unknown')).titles, isEmpty);
    });
  });

  group('France24Provider search', () {
    test('words match programme titles regardless of accents and case', () async {
      final provider = providerOver(RecordedFrance24());
      expect((await provider.search('AVEC judith')).single.ref, _ref(avecJudith));
      expect((await provider.search('cafe sports')).single.title, 'Café des sports');
      expect((await provider.search("c'est en")).single.title, "C'est en France");
    });

    test('nothing matches a nonsense or blank query', () async {
      final server = RecordedFrance24();
      final provider = providerOver(server);
      expect(await provider.search('zzzz'), isEmpty);
      server.requests.clear();
      expect(await provider.search('   '), isEmpty);
      expect(server.requests, isEmpty);
    });
  });

  group('France24Provider titles', () {
    test('a programme is a show with square and wide artwork', () async {
      final show = (await providerOver(RecordedFrance24()).title(_ref(avecJudith)))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Avec Judith');
      expect(show.posterUrl, contains('FR-AVEC-JUDITH-1-1.jpg'));
      expect(show.backdropUrl, isNot(equals(show.posterUrl)));
      expect(show.summary, isNotEmpty);
    });

    test('an unknown programme, clip or malformed id is null', () async {
      final provider = providerOver(RecordedFrance24());
      expect(await provider.title(_ref('WBMZ1-F24-FR-20200101')), isNull);
      expect(await provider.title(_ref('v/00000000-0000-0000-0000-000000000000')), isNull);
      expect(await provider.title(_ref('a/b/c/d')), isNull);
      expect(await provider.children(_ref('a/b/c/d')), isEmpty);
    });

    test('a clip is looked up by its own id', () async {
      final clip = (await providerOver(RecordedFrance24()).title(_ref('v/$clipWithTwoFormats')))!;
      expect(clip.kind, ReplayKind.clip);
      expect(clip.durationSeconds, 450);
      expect(clip.isPlayable, isTrue);
    });

    test('an item with no file is left out of lists', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      final list = (server.videoFeed!['result'] as Map<String, dynamic>)['list'] as List;
      (list.first as Map<String, dynamic>)['formats'] = <Object>[];
      final titles = (await providerOver(server).listing('videos')).titles;
      expect(titles.map((t) => t.ref.nativeId), ['v/$clipWithTwoFormats']);
    });

    test('rights windows are predicted in lists without calling playback', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      final past = DateTime.utc(2026, 9).millisecondsSinceEpoch;
      final future = DateTime.utc(2026, 12).millisecondsSinceEpoch;
      _setValidity(server.videoFeed!, clipWithAllFormats, until: past);
      _setValidity(server.videoFeed!, clipWithTwoFormats, from: future, until: future + 86400000);
      final titles = (await providerOver(server).listing('videos')).titles;
      expect(titles[0].availability, ReplayAvailability.expired);
      expect(titles[1].availability, ReplayAvailability.upcoming);
      expect(titles[1].availableUntil, DateTime.fromMillisecondsSinceEpoch(future + 86400000, isUtc: true));
    });
  });

  group('France24Provider playback', () {
    test('a clip offers its distinct files from best to worst', () async {
      final playback = await providerOver(RecordedFrance24()).playback(_ref('v/$clipWithAllFormats'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['1080p', '720p', '576p']);
      expect(playback.streams.first.url.toString(), endsWith('FR_20261021_071614_072101_CS_8000.mp4'));
      expect(playback.streams.last.url.toString(), endsWith('FR_20261021_071614_072101_CS.mp4'));
      expect(playback.streams.every((s) => s.url.host == 'vod-france24.akamaized.net'), isTrue);
      expect(playback.streams.every((s) => s.headers.isEmpty), isTrue);
    });

    test('an edition without a 576p file offers two streams', () async {
      final playback = await providerOver(RecordedFrance24()).playback(_ref('$avecJudith/e/$avecJudithEdition'));
      expect(playback.streams.map((s) => s.label), ['1080p', '720p']);
      expect(playback.streams.last.url.path, startsWith('/hd/'));
    });

    test('a lone MP4 file is offered under its own name', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      final list = (server.videoFeed!['result'] as Map<String, dynamic>)['list'] as List;
      (list[0] as Map<String, dynamic>)['formats'] = [
        {'code': 'MP4', 'url': 'https://vod-france24.akamaized.net/fr/vod/2026/10/21/a.mp4'},
        {'code': 'MP4-FULL-HD', 'url': 'https://vod-france24.akamaized.net/fr/vod/2026/10/21/a.mp4'},
        {'code': 'MP4-SD', 'url': 'https://vod-france24.akamaized.net/fr/vod/2026/10/21/b.mp4'},
      ];
      final playback = await providerOver(server).playback(_ref('v/$clipWithAllFormats'));
      expect(playback.streams.map((s) => s.label), ['1080p', '576p']);
    });

    test('a video past its rights window is expired', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      _setValidity(server.videoFeed!, clipWithAllFormats, until: DateTime.utc(2026, 9).millisecondsSinceEpoch);
      final playback = await providerOver(server).playback(_ref('v/$clipWithAllFormats'));
      expect(playback.availability, ReplayAvailability.expired);
      expect(playback.streams, isEmpty);
    });

    test('a video before its rights window is upcoming', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      _setValidity(server.videoFeed!, clipWithAllFormats, from: DateTime.utc(2026, 12).millisecondsSinceEpoch);
      final playback = await providerOver(server).playback(_ref('v/$clipWithAllFormats'));
      expect(playback.availability, ReplayAvailability.upcoming);
    });

    test('a video that lists no file is unavailable with a reason', () async {
      final server = RecordedFrance24()..videoFeed = fixture('videos');
      final list = (server.videoFeed!['result'] as Map<String, dynamic>)['list'] as List;
      (list[1] as Map<String, dynamic>)['formats'] = <Object>[];
      final playback = await providerOver(server).playback(_ref('v/$clipWithTwoFormats'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, isNotEmpty);
    });

    test('a video the feed no longer lists is expired', () async {
      final playback = await providerOver(RecordedFrance24()).playback(_ref('v/00000000-0000-0000-0000-000000000000'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('a show or a season is never played directly', () async {
      final provider = providerOver(RecordedFrance24());
      expect((await provider.playback(_ref(avecJudith))).isPlayable, isFalse);
      expect((await provider.playback(_ref('$avecJudith/2026'))).isPlayable, isFalse);
    });

    test('a rejected application key is reported without throwing', () async {
      final server = RecordedFrance24()
        ..status = 401
        ..requests.clear();
      final playback = await providerOver(server).playback(_ref('v/$clipWithAllFormats'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('app key'));
    });

    test('rate limiting is reported and later requests wait for Retry-After', () async {
      final server = RecordedFrance24()
        ..status = 429
        ..statusHeaders = {'retry-after': '30'};
      final provider = providerOver(server);
      final first = await provider.playback(_ref('v/$clipWithAllFormats'));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));
      final sent = server.requests.length;
      final second = await provider.playback(_ref('v/$clipWithTwoFormats'));
      expect(second.message, contains('retry in'));
      expect(server.requests.length, sent);
    });
  });

  group('France24 images', () {
    const square = 'https://s.france24.com/media/display/f41e198a/FR-AVEC-JUDITH-1-1.jpg';

    test('a portrait box asks for a 2:3 crop at an accepted width', () {
      expect(france24ImageUrl(square, width: 300, height: 450), '$_host/f41e198a/w:320/p:2x3/FR-AVEC-JUDITH-1-1.jpg');
    });

    test('a landscape box asks for a 16:9 crop', () {
      expect(france24ImageUrl(square, width: 640, height: 360), '$_host/f41e198a/w:640/p:16x9/FR-AVEC-JUDITH-1-1.jpg');
      expect(france24ImageUrl(square, width: 5000, height: 2000), contains('/w:1920/p:'));
    });

    test('without a size the picture is a 640 wide 16:9 crop', () {
      expect(france24ImageUrl(square), '$_host/f41e198a/w:640/p:16x9/FR-AVEC-JUDITH-1-1.jpg');
    });

    test('an already sized reference is re-cropped, not stacked', () {
      const sized = 'https://s.france24.com/media/display/f41e198a/w:720/p:16x9/FR-AVEC-JUDITH-1-1.jpg';
      expect(france24ImageUrl(sized, width: 200, height: 300), '$_host/f41e198a/w:200/p:2x3/FR-AVEC-JUDITH-1-1.jpg');
    });

    test('spaces in a file name are encoded and vector pictures are kept', () {
      const spaced = 'https://s.france24.com/media/display/abc/FR-CAFE DES SPORTS_1-1.jpg';
      expect(
        france24ImageUrl(spaced, width: 480, height: 270),
        contains('/w:480/p:16x9/FR-CAFE%20DES%20SPORTS_1-1.jpg'),
      );
      const vector = 'https://s.france24.com/media/display/abc/logo.svg';
      expect(france24ImageUrl(vector, width: 480, height: 270), vector);
    });

    test('shows and episodes hold artwork this provider owns', () async {
      final provider = providerOver(RecordedFrance24());
      final rails = await provider.home();
      final references = [
        for (final t in [for (final r in rails) ...r.titles]) ...[?t.posterUrl, ?t.backdropUrl],
      ];
      expect(references, isNotEmpty);
      expect(references.every(provider.ownsImage), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(references.first, width: 320, height: 180), contains('/w:320/p:16x9/'));
    });
  });

  group('France24 ids', () {
    test('every kind of id survives a round trip', () {
      for (final native in [
        avecJudith,
        '$avecJudith/2026',
        '$avecJudith/e/$avecJudithEdition',
        'v/$clipWithAllFormats',
      ]) {
        expect(France24Id.tryParse(native)?.toString(), native);
      }
    });

    test('a programme and a clip with the same id syntax stay apart', () {
      expect(France24Id.tryParse('WBMZ1-F24-FR-20200101')!.isShow, isTrue);
      expect(France24Id.tryParse('v/WBMZ1-F24-FR-20200101')!.isClip, isTrue);
    });

    test('malformed ids are rejected', () {
      for (final native in ['', '/', 'a//b', 'a/12', 'a/x/b', 'a/e', 'a/2026/b', 'v/a/b']) {
        expect(France24Id.tryParse(native), isNull, reason: native);
      }
    });
  });
}

const _host = 'https://s.france24.com/media/display';
