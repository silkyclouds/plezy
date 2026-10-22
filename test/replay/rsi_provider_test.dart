import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rsi/rsi_images.dart';
import 'package:plezy/replay/providers/rsi/rsi_unit.dart';
import 'package:plezy/replay/providers/srg/srg_mapper.dart';

import 'rsi_fake_api.dart';
import 'srg_test_support.dart';

ReplayRef _ref(String native) => ReplayRef('rsi', native);

void main() {
  group('RsiProvider source', () {
    test('is a clear Italian source paged by hundreds', () {
      final source = rsiProvider().source;
      expect((source.id, source.name, source.language), ('rsi', 'RSI Play', 'it'));
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 100);
    });

    test('predicts availability for viewers abroad', () {
      expect(rsiProvider(), isA<ReplayAvailabilityPredictor>());
    });
  });

  group('RsiProvider browsing', () {
    test('categories leave out sign language and audio description', () async {
      final categories = await rsiProvider().categories();
      expect(categories, hasLength(9));
      expect(categories.map((c) => c.title), containsAll(['Info', 'Kids', 'Intrattenimento']));
      expect(categories.map((c) => c.id).toSet().intersection({'80', '90'}), isEmpty);
    });

    test('home rows are Italian and keep only what plays here', () async {
      final rails = await rsiProvider().home();
      expect(rails.map((r) => r.id), ['latest', 'trending']);
      expect(rails.map((r) => r.title), ['Ultimi episodi', 'In tendenza']);
      expect(rails.last.titles.map((t) => t.title), ['Telegiornale, 20:00']);
      expect(rails.first.titles.single.showTitle, 'Falò');
    });

    test('a topic page keeps content rows and drops the media element', () async {
      final rails = await rsiProvider().category(rsiNewsTopic);
      expect(rails.map((r) => r.title), [
        'La nostra proposta',
        'I video più recenti',
        'Ti potrebbero interessare',
        'Inchieste',
        'Ticino, Grigioni e Insubria',
        'Svizzera',
        'Mondo',
        'Svizzerando',
      ]);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('the listing keeps real posters and drops generic ones', () async {
      final page = await rsiProvider().listing(replayAllBrowseId);
      expect(page.totalCount, 5);
      final generic = page.titles.firstWhere((t) => t.title == '#startuppers');
      expect(generic.posterUrl, isNull);
      expect(generic.backdropUrl, startsWith('https://il.rsi.ch/rsi-api/resize/image/v2/WEBVISUAL/'));
      final real = page.titles.firstWhere((t) => t.title.startsWith('1,2,3'));
      expect(real.posterUrl, contains('/POSTER/'));
    });

    test('a row listing flags the videos blocked from this country', () async {
      final page = await rsiProvider().listing('MediaSection/8af77879-82a3-4e63-a54e-f49d178aa63c');
      expect(page.titles.map((t) => t.availability), [
        ReplayAvailability.geoBlocked,
        ReplayAvailability.playable,
        ReplayAvailability.geoBlocked,
      ]);
    });
  });

  group('RsiProvider search', () {
    test('shows come first, then videos of this unit only', () async {
      final provider = rsiProvider();
      final results = await provider.search('falo');
      expect(results.take(5).every((t) => t.kind == ReplayKind.show), isTrue);
      expect(results.first.title, 'Falò');
      expect(results.where((t) => t.kind != ReplayKind.show), hasLength(4));
      final romansh = await provider.search('romancio');
      expect(romansh.map((t) => t.ref.nativeId), ['video:i1']);
    });

    test('sign-language copies and described twins are hidden', () async {
      final titles = (await rsiProvider().search('quotidiano')).map((t) => t.title);
      expect(titles, ['Il Quotidiano', 'Blind', 'Scuola (con audiodescrizione)']);
    });
  });

  group('RsiProvider seasons', () {
    test('a numbered series is one season with cleaned episode titles', () async {
      final provider = rsiProvider();
      final seasons = await provider.children(_ref('show:$rsiAlpinismoShow'));
      expect((seasons.single.title, seasons.single.seasonNumber, seasons.single.childCount), ('Stagione 1', 1, 7));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7]);
      expect(episodes.first.title, 'La selezione');
      expect(episodes.first.showTitle, 'Scuola di alpinismo');
      expect(episodes.every((e) => e.availability == ReplayAvailability.geoBlocked), isTrue);
    });

    test('a bare episode title is kept as it is', () async {
      final provider = rsiProvider();
      final season = (await provider.children(_ref('show:$rsiAgentShow'))).single;
      expect(season.title, 'Stagione 2');
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.title), [
        'Episodio 1',
        'Episodio 2',
        'Episodio 3',
        'Episodio 4',
        'Episodio 5',
        'Episodio 6',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
    });

    test('a long daily show is listed by broadcast year', () async {
      final provider = rsiProvider();
      final seasons = await provider.children(_ref('show:daily'));
      expect(seasons.map((s) => s.title), ['2025', '2026']);
      expect(await provider.children(seasons.first.ref), hasLength(157));
    });

    test('a missing show has no children and no title', () async {
      final provider = rsiProvider();
      expect(await provider.children(_ref('show:nope')), isEmpty);
      expect(await provider.title(_ref('show:nope')), isNull);
      expect(await provider.title(_ref('season:$rsiAlpinismoShow/s5')), isNull);
    });
  });

  group('RsiProvider titles', () {
    test('a news episode points at the year of its daily show', () async {
      final title = await rsiProvider().title(_ref('video:$rsiFaloVideo'));
      expect(title!.kind, ReplayKind.episode);
      expect(title.showTitle, 'Falò');
      expect(title.seasonRef, _ref('season:703565/y2026'));
      expect(title.durationSeconds, 44);
      expect(title.ref.source, 'rsi');
    });

    test('a film of the film show is a movie without a parent', () {
      final film = srgVideo('rsi', 'f1', '2026-10-19T20:00:00+02:00', show: '702738');
      final title = SrgMapper(rsiUnit).fromMedia(film)!;
      expect((title.kind, title.showRef, title.seasonRef), (ReplayKind.movie, null, null));
    });

    test('an item of a sister unit is not a title', () {
      expect(SrgMapper(rsiUnit).fromMedia(srgVideo('rtr', 'r1', '2026-10-01T20:00:00+02:00')), isNull);
    });
  });

  group('RsiProvider numbering', () {
    final numbering = rsiUnit.numbering;

    test('Italian labels give season and episode', () {
      expect(numbering.numbers({'title': 'Titolo (Stagione 2, Episodio 3)'}), (season: 2, episode: 3));
      expect(numbering.numbers({'title': 'Titolo (Puntata 5)'}), (season: null, episode: 5));
      expect(numbering.numbers({'title': 'Ep. 4 - Tuoni e fulmini'}), (season: null, episode: 4));
    });

    test('a leading label is removed from the title', () {
      expect(numbering.cleanTitle('Ep. 4 - Tuoni e fulmini'), 'Tuoni e fulmini');
      expect(numbering.cleanTitle('Titolo (Stagione 2, Episodio 3)'), 'Titolo');
      expect(numbering.cleanTitle('Episodio 6'), 'Episodio 6');
    });

    test('a word that merely ends in ep is not a label', () {
      expect(numbering.numbers({'title': 'Dep 5 minuti'}), (season: null, episode: null));
    });
  });

  group('RsiProvider playback', () {
    test('a news programme yields its HLS master with its time bounds', () async {
      final playback = await rsiProvider().playback(_ref('video:$rsiTelegiornaleVideo'));
      expect(playback.isPlayable, isTrue);
      final url = playback.streams.single.url;
      expect(url.host, 'rsi-vod-il-amd.akamaized.net');
      expect(url.path, endsWith('/master.m3u8'));
      expect(url.queryParameters, {'start': '0.0', 'end': '675.0'});
      expect(playback.streams.single.label, 'IT');
      expect(playback.streams.single.headers, isEmpty);
    });

    test('a magazine with subtitles plays as well', () async {
      expect((await rsiProvider().playback(_ref('video:$rsiQuotidianoVideo'))).isPlayable, isTrue);
    });

    test('a geoblocked programme says so', () async {
      final playback = await rsiProvider().playback(_ref('video:$rsiGeoVideo'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('a protected stream is reported, never offered', () async {
      final playback = await rsiProvider().playback(_ref('video:drm'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.message, contains('FAIRPLAY'));
    });

    test('ended, missing and progressive programmes', () async {
      final provider = rsiProvider();
      expect((await provider.playback(_ref('video:ended'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('video:gone'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('video:mp4'))).streams.single.url.path, endsWith('.mp4'));
    });
  });

  group('RsiProvider availability forecast', () {
    test('a series closed to the world is blocked for a viewer abroad', () async {
      final provider = rsiProvider();
      final season = (await provider.children(_ref('show:$rsiAlpinismoShow'))).single;
      final episodes = await provider.children(season.ref);
      final verdicts = await provider.predictAvailability([season, ...episodes], 'BE');
      expect(verdicts.keys, containsAll([season.ref, ...episodes.map((e) => e.ref)]));
      expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
    });

    test('a viewer in Switzerland is never greyed out', () async {
      final provider = rsiProvider();
      final season = (await provider.children(_ref('show:$rsiAgentShow'))).single;
      final episodes = await provider.children(season.ref);
      expect(await provider.predictAvailability([season, ...episodes], 'CH'), isEmpty);
    });

    test('an open item stays open for a viewer abroad', () async {
      final provider = rsiProvider();
      final titles = [for (final rail in await provider.home()) ...rail.titles];
      expect(await provider.predictAvailability(titles, 'BE'), isEmpty);
    });
  });

  group('RsiProvider artwork', () {
    const base = 'https://il.rsi.ch/rsi-api/resize/image/v2';

    test('a numbered picture gets a width bucket', () {
      expect(rsiImageUrl('$base/WEBVISUAL/123', width: 300), '$base/WEBVISUAL/123/scale/width/320');
      expect(rsiImageUrl('$base/EPISODE_IMAGE/9', width: 5000), '$base/EPISODE_IMAGE/9/scale/width/1920');
      expect(rsiImageUrl('$base/POSTER/7', width: 200, height: 300), '$base/POSTER/7/scale/width/320');
      expect(rsiImageUrl('$base/WEBVISUAL/123'), '$base/WEBVISUAL/123/scale/width/640');
    });

    test('static and generic pictures are used as given', () {
      expect(rsiImageUrl('$base/public/binary/news.png', width: 300), '$base/public/binary/news.png');
      const generic = 'https://il.srgssr.ch/image-service/dynamic/cf9050e.jpg';
      expect(rsiImageUrl(generic, width: 300), generic);
    });

    test('the provider claims only RSI and SRG pictures', () {
      final provider = rsiProvider();
      expect(provider.ownsImage('$base/WEBVISUAL/123'), isTrue);
      expect(provider.ownsImage('https://il.srgssr.ch/image-service/dynamic/x.jpg'), isTrue);
      expect(provider.ownsImage('https://download-media.srf.ch/world/image/a.jpg'), isFalse);
      expect(provider.imageUrl('$base/WEBVISUAL/123', width: 300), endsWith('/scale/width/320'));
    });
  });

  group('RsiProvider requests', () {
    test('lists are cached and sent to the RSI business unit', () async {
      final log = <http.Request>[];
      final provider = rsiProvider(log: log);
      await provider.home();
      final first = log.length;
      await provider.home();
      expect(log.length, first);
      expect(log.first.headers['User-Agent'], contains('Plezy-Replay'));
      expect(log.first.url.path, startsWith('/integrationlayer/2.0/rsi/'));
    });

    test('playback asks for the RSI urn and is never cached', () async {
      final log = <http.Request>[];
      final provider = rsiProvider(log: log);
      await provider.playback(_ref('video:$rsiTelegiornaleVideo'));
      await provider.playback(_ref('video:$rsiTelegiornaleVideo'));
      expect(log, hasLength(2));
      expect(log.first.url.path, endsWith('/mediaComposition/byUrn/urn:rsi:video:$rsiTelegiornaleVideo'));
    });
  });
}
