import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/srfplay/srfplay_images.dart';
import 'package:plezy/replay/providers/srfplay/srfplay_unit.dart';
import 'package:plezy/replay/providers/srg/srg_mapper.dart';

import 'srfplay_fake_api.dart';
import 'srg_test_support.dart';

ReplayRef _ref(String native) => ReplayRef('srfplay', native);

void main() {
  group('SrfPlayProvider source', () {
    test('is a clear German source paged by hundreds', () {
      final source = srfProvider().source;
      expect((source.id, source.name, source.language), ('srfplay', 'SRF Play', 'de'));
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 100);
    });

    test('predicts availability for viewers abroad', () {
      expect(srfProvider(), isA<ReplayAvailabilityPredictor>());
    });
  });

  group('SrfPlayProvider browsing', () {
    test('categories leave out the accessibility copies', () async {
      final categories = await srfProvider().categories();
      expect(categories, hasLength(11));
      expect(categories.map((c) => c.title), containsAll(['Kids', 'Dokus & Reportagen']));
      expect(categories.map((c) => c.title), isNot(contains('Gebärdensprache')));
      expect(categories.map((c) => c.title), isNot(contains('Audiodeskription')));
    });

    test('home rows are German and drop empty rows', () async {
      final rails = await srfProvider().home();
      expect(rails.map((r) => r.id), ['latest', 'trending']);
      expect(rails.first.title, 'Neueste Folgen');
      expect(rails.every((r) => r.titles.every((t) => t.availability == ReplayAvailability.playable)), isTrue);
      expect(rails.first.titles.first.title, 'Vom tiefsten zum höchsten Punkt der Schweiz');
    });

    test('a topic page keeps the rows that hold videos or shows', () async {
      final rails = await srfProvider().category(srfDokTopic);
      expect(rails.map((r) => r.id), [
        'f0c9649d-c8e3-4761-84d5-5e7522443bed',
        srfRowWithBlocked,
        '86c7af51-be89-4492-8c79-817abc938ba5',
      ]);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(rails[1].title, 'Unsere neusten Dokumentationen');
      expect(rails[1].titles, hasLength(3));
      expect(rails[1].moreBrowseId, 'MediaSection/$srfRowWithBlocked');
      expect(rails[2].titles.first.showTitle, 'Reporter');
    });

    test('a category id that is not a topic id gives no rows', () async {
      final log = <http.Request>[];
      expect(await srfProvider(log: log).category('../x'), isEmpty);
      expect(log, isEmpty);
    });

    test('the listing hides sign-language and described copies', () async {
      final page = await srfProvider().listing(replayAllBrowseId);
      expect(page.totalCount, 3);
      expect(page.titles.map((t) => t.title), ['#SayHi', '#SayHi – Eure Videos', '1 gegen 100']);
      expect((await srfProvider().listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a row listing flags the videos blocked from this country', () async {
      final page = await srfProvider().listing('MediaSection/$srfRowWithBlocked');
      expect(page.titles.map((t) => t.availability), [
        ReplayAvailability.playable,
        ReplayAvailability.geoBlocked,
        ReplayAvailability.playable,
        ReplayAvailability.playable,
      ]);
      expect(page.totalCount, 5);
    });

    test('an unknown listing id is empty', () async {
      final provider = srfProvider();
      expect((await provider.listing('nonsense')).titles, isEmpty);
      expect((await provider.listing('MediaSection/../x')).titles, isEmpty);
    });
  });

  group('SrfPlayProvider search', () {
    test('shows come first and sign-language copies are left out', () async {
      final results = await srfProvider().search('kassensturz');
      expect(results.where((t) => t.kind == ReplayKind.show).map((t) => t.title), [
        'Kassensturz',
        'Kassensturz - Dein Recht',
      ]);
      expect(results.take(2).every((t) => t.kind == ReplayKind.show), isTrue);
      expect(results.where((t) => t.kind != ReplayKind.show), hasLength(4));
      expect(results.map((t) => t.ref).toSet(), hasLength(results.length));
    });

    test('a described copy is hidden only next to its original', () async {
      final provider = srfProvider();
      expect((await provider.search('arena')).map((t) => t.title), ['Arena']);
      expect((await provider.search('bestatter')).map((t) => t.title), ['Der Bestatter mit Audiodeskription']);
    });

    test('audio results are dropped and a blank query asks nothing', () async {
      final log = <http.Request>[];
      final provider = srfProvider(log: log);
      final results = await provider.search('radio');
      expect(results.map((t) => t.title), isNot(contains('Radio')));
      log.clear();
      expect(await provider.search('  '), isEmpty);
      expect(log, isEmpty);
    });
  });

  group('SrfPlayProvider seasons', () {
    test('a numbered show lists its seasons, then its extras', () async {
      final seasons = await srfProvider().children(_ref('show:$srfDokId'));
      expect(seasons.map((s) => s.title), ['Staffel 4', 'Bonus']);
      expect(seasons.map((s) => s.seasonNumber), [4, 0]);
      expect(seasons.map((s) => s.childCount), [4, 1]);
      expect(seasons.first.ref, _ref('season:$srfDokId/s4'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show:$srfDokId')), isTrue);
    });

    test('a season lists its episodes in order without the label', () async {
      final provider = srfProvider();
      final season = (await provider.children(_ref('show:$srfDokId'))).first;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.first.title, 'Vom tiefsten zum höchsten Punkt der Schweiz');
      expect(episodes.first.seasonNumber, 4);
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.showTitle, 'DOK – Hoch hinaus');
      expect(episodes.first.durationSeconds, greaterThan(2000));
    });

    test('the extras season holds the unnumbered clip', () async {
      final provider = srfProvider();
      final bonus = (await provider.children(_ref('show:$srfDokId'))).last;
      final clips = await provider.children(bonus.ref);
      expect(clips.single.kind, ReplayKind.clip);
      expect(clips.single.episodeNumber, isNull);
      expect(clips.single.title, 'Making of');
    });

    test('a show with no numbers has one season named after it', () async {
      final provider = srfProvider();
      final seasons = await provider.children(_ref('show:geo'));
      expect((seasons.single.title, seasons.single.seasonNumber, seasons.single.childCount), ('DOK', 1, 3));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.availability), [
        ReplayAvailability.geoBlocked,
        ReplayAvailability.playable,
        ReplayAvailability.playable,
      ]);
      expect(episodes.first.airDate!.isAfter(episodes.last.airDate!), isTrue);
    });

    test('a long daily show is listed by broadcast year', () async {
      final provider = srfProvider();
      final seasons = await provider.children(_ref('show:daily'));
      expect(seasons.map((s) => s.title), ['2025', '2026']);
      final y2026 = await provider.children(seasons.last.ref);
      expect(y2026, hasLength(293));
      expect(y2026.every((e) => e.airDate!.year == 2026), isTrue);
    });

    test('a show and a season resolve by reference', () async {
      final provider = srfProvider();
      final show = await provider.title(_ref('show:$srfDokId'));
      expect((show!.kind, show.title, show.ref.source), (ReplayKind.show, 'DOK – Hoch hinaus', 'srfplay'));
      final season = await provider.title(_ref('season:$srfDokId/s4'));
      expect((season!.kind, season.seasonNumber), (ReplayKind.season, 4));
      expect(await provider.title(_ref('season:$srfDokId/s9')), isNull);
      expect(await provider.title(_ref('show:nope')), isNull);
      expect(await provider.children(_ref('garbage')), isEmpty);
    });
  });

  group('SrfPlayProvider titles', () {
    test('an episode is read from its media composition', () async {
      final title = await srfProvider().title(_ref('video:$srfTagesschauVideo'));
      expect(title!.kind, ReplayKind.episode);
      expect(title.title, 'Tagesschau vom 21.10.2026: Hauptausgabe');
      expect(title.showTitle, 'Tagesschau');
      expect(title.availability, ReplayAvailability.playable);
      expect(title.availableUntil, isNull);
      expect(title.durationSeconds, 1429);
      expect(title.seasonRef, _ref('season:ff969c14-c5a7-44ab-ab72-14d4c9e427a9/y2026'));
    });

    test('a film of the film show is a movie without a parent', () {
      final mapper = SrgMapper(srfPlayUnit);
      final film = srgVideo('srf', 'f1', '2026-10-17T20:00:00+02:00', show: 'c5f011e6-e1d0-0001-94b7-cb557740172f');
      final title = mapper.fromMedia(film)!;
      expect((title.kind, title.showRef, title.seasonRef), (ReplayKind.movie, null, null));
    });

    test('rights that ended or have not begun are predicted', () {
      final mapper = SrgMapper(srfPlayUnit);
      final ended = {...srgVideo('srf', 'e1', '2020-01-01T20:00:00+01:00'), 'validTo': '2021-01-01T00:00:00+01:00'};
      final later = {...srgVideo('srf', 'e2', '2020-01-01T20:00:00+01:00'), 'validFrom': '2999-01-01T00:00:00+01:00'};
      expect(mapper.fromMedia(ended)!.availability, ReplayAvailability.expired);
      expect(mapper.fromMedia(later)!.availability, ReplayAvailability.upcoming);
    });

    test('the far-future end date means no end', () {
      final item = {...srgVideo('srf', 'n1', '2026-01-01T20:00:00+01:00'), 'validTo': '2099-12-31T23:59:00+01:00'};
      expect(SrgMapper(srfPlayUnit).fromMedia(item)!.availableUntil, isNull);
    });

    test('sister-unit and audio items are not titles', () {
      final mapper = SrgMapper(srfPlayUnit);
      expect(mapper.fromMedia(srgVideo('rtr', 'r1', '2026-01-01T00:00:00+01:00')), isNull);
      expect(mapper.fromMedia({'id': 'a', 'urn': 'urn:srf:audio:a', 'mediaType': 'AUDIO', 'type': 'EPISODE'}), isNull);
    });
  });

  group('SrfPlayProvider numbering', () {
    final numbering = srfPlayUnit.numbering;

    test('the label in the title gives season and episode', () {
      expect(numbering.numbers({'title': 'Ein Titel (Staffel 4, Folge 3)'}), (season: 4, episode: 3));
      expect(numbering.numbers({'title': 'Ein Titel (Folge 7)'}), (season: null, episode: 7));
      expect(numbering.numbers({'title': 'Folge 2: Der Anfang'}), (season: null, episode: 2));
    });

    test('the structured fields win over the title', () {
      final item = {
        'title': 'Ein Titel (Staffel 9, Folge 9)',
        'episode': {'seasonNumber': 2, 'number': 5},
      };
      expect(numbering.numbers(item), (season: 2, episode: 5));
    });

    test('the label is removed from the displayed title only', () {
      expect(numbering.cleanTitle('Ein Titel (Staffel 4, Folge 4)'), 'Ein Titel');
      expect(
        numbering.cleanTitle('Ein Titel – mit Audiodeskription (Staffel 4, Folge 4)'),
        'Ein Titel – mit Audiodeskription',
      );
      expect(numbering.cleanTitle('Folge 2: Der Anfang'), 'Der Anfang');
      expect(numbering.cleanTitle('Folge 2'), 'Folge 2');
    });
  });

  group('SrfPlayProvider playback', () {
    test('a clear programme yields its HLS master, query intact', () async {
      final playback = await srfProvider().playback(_ref('video:$srfTagesschauVideo'));
      expect(playback.isPlayable, isTrue);
      final url = playback.streams.single.url;
      expect(url.host, 'srf-vod-amd.akamaized.net');
      expect(url.path, endsWith('/master.m3u8'));
      expect(url.queryParameters['webvttbaseurl'], 'subtitles.eai-general.aws.srf.ch');
      expect(playback.streams.single.label, 'DE');
      expect(playback.streams.single.headers, isEmpty);
    });

    test('a geoblocked programme says so', () async {
      final playback = await srfProvider().playback(_ref('video:$srfGeoVideo'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('no streams and not playable abroad is geoblocked', () async {
      final provider = srfProvider();
      expect((await provider.playback(_ref('video:no-stream-abroad'))).availability, ReplayAvailability.geoBlocked);
      expect((await provider.playback(_ref('video:no-stream'))).availability, ReplayAvailability.expired);
    });

    test('a protected stream is reported, never offered', () async {
      final playback = await srfProvider().playback(_ref('video:drm'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('WIDEVINE'));
    });

    test('block reasons map to their availability', () async {
      final provider = srfProvider();
      Future<ReplayAvailability> reason(String id) async => (await provider.playback(_ref('video:$id'))).availability;
      expect(await reason('ended'), ReplayAvailability.expired);
      expect(await reason('upcoming'), ReplayAvailability.upcoming);
      expect(await reason('age'), ReplayAvailability.timeSlotRestricted);
      expect(await reason('gone'), ReplayAvailability.expired);
    });

    test('a progressive file is the fallback when there is no HLS', () async {
      final playback = await srfProvider().playback(_ref('video:mp4'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('.mp4'));
    });

    test('shows and seasons are never played directly', () async {
      final provider = srfProvider();
      expect((await provider.playback(_ref('show:$srfDokId'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('season:$srfDokId/s4'))).isPlayable, isFalse);
    });

    test('rate limiting is reported and later calls wait', () async {
      final log = <http.Request>[];
      final provider = srfProvider(log: log);
      final first = await provider.playback(_ref('video:limited'));
      expect(first.message, contains('30'));
      final before = log.length;
      expect((await provider.playback(_ref('video:$srfTagesschauVideo'))).message, contains('Rate limited'));
      expect(log.length, before);
    });
  });

  group('SrfPlayProvider availability forecast', () {
    /// A list as seen from a Swiss address: the server blocks nothing, but two items are Swiss-only.
    http.Response swissView(http.Request request) {
      if (srgPath(request) != 'srf/mediaList/video/trending') return srfRoute(request);
      return srgJson({
        'mediaList': [
          srgVideo('srf', 'open1', '2026-10-01T20:00:00+02:00', show: 's1', count: 3),
          srgVideo('srf', 'swiss1', '2026-10-02T20:00:00+02:00', show: 's1', count: 3, playableAbroad: false),
        ],
      });
    }

    test('a Swiss-only title is blocked for a viewer abroad', () async {
      final provider = srfProvider(route: swissView);
      final titles = [for (final rail in await provider.home()) ...rail.titles];
      expect(titles.every((t) => t.availability == ReplayAvailability.playable), isTrue);
      final verdicts = await provider.predictAvailability(titles, 'BE');
      expect(verdicts, {_ref('video:swiss1'): ReplayAvailability.geoBlocked});
    });

    test('a viewer in Switzerland is never greyed out', () async {
      final provider = srfProvider(route: swissView);
      final titles = [for (final rail in await provider.home()) ...rail.titles];
      expect(await provider.predictAvailability(titles, 'CH'), isEmpty);
      expect(await provider.predictAvailability(titles, 'ch'), isEmpty);
    });

    test('a title the catalogue never showed is left out', () async {
      const unseen = ReplayTitle(ref: ReplayRef('srfplay', 'video:unseen'), kind: ReplayKind.episode, title: 'x');
      expect(await srfProvider().predictAvailability([unseen], 'BE'), isEmpty);
    });

    test('a season is blocked only when every episode is', () async {
      final provider = srfProvider();
      final closed = (await provider.children(_ref('show:closed'))).single;
      final open = (await provider.children(_ref('show:geo'))).single;
      final verdicts = await provider.predictAvailability([closed, open], 'BE');
      expect(verdicts, {closed.ref: ReplayAvailability.geoBlocked});
    });
  });

  group('SrfPlayProvider artwork', () {
    const original = 'https://download-media.srf.ch/world/image/default/2026/10/imported-image-1';

    test('a picture goes through the resizer at a supported width', () {
      final url = Uri.parse(srfPlayImageUrl(original, width: 300));
      expect((url.host, url.path), ('il.srgssr.ch', '/images/'));
      expect(url.queryParameters, {'imageUrl': original, 'format': 'webp', 'width': '320'});
      expect(Uri.parse(srfPlayImageUrl(original, width: 5000)).queryParameters['width'], '1920');
    });

    test('a small box gets the smallest width and no box gets 480', () {
      expect(Uri.parse(srfPlayImageUrl(original, width: 200, height: 300)).queryParameters['width'], '240');
      expect(Uri.parse(srfPlayImageUrl(original)).queryParameters['width'], '480');
    });

    test('resized and generic pictures are used as given', () {
      const generic = 'https://il.srgssr.ch/image-service/dynamic/096a0a5.jpg';
      expect(srfPlayImageUrl(generic, width: 300), generic);
      const resized = 'https://il.srgssr.ch/images/?imageUrl=x&format=webp&width=320';
      expect(srfPlayImageUrl(resized, width: 300), resized);
    });

    test('the provider claims only SRG pictures', () {
      final provider = srfProvider();
      expect(provider.ownsImage(original), isTrue);
      expect(provider.ownsImage('https://il.srgssr.ch/image-service/dynamic/x.jpg'), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(original, width: 300), contains('width=320'));
    });

    test('a generic poster falls back to the landscape picture', () async {
      final provider = srfProvider(
        route: (request) {
          if (srgPath(request) != 'srf/showList/tv/alphabetical') return srfRoute(request);
          return srgJson({
            'showList': [
              {
                'id': 's1',
                'title': 'Sendung',
                'numberOfEpisodes': 3,
                'posterImageUrl': 'https://il.srgssr.ch/image-service/dynamic/x.jpg',
                'posterImageIsFallbackUrl': true,
                'imageUrl': original,
              },
            ],
          });
        },
      );
      final show = (await provider.listing(replayAllBrowseId)).titles.single;
      expect((show.posterUrl, show.backdropUrl), (null, original));
    });
  });

  group('SrfPlayProvider requests', () {
    test('lists are cached and identify the app', () async {
      final log = <http.Request>[];
      final provider = srfProvider(log: log);
      await provider.home();
      final first = log.length;
      await provider.home();
      expect(log.length, first);
      expect(log.first.headers['User-Agent'], contains('Plezy-Replay'));
      expect(log.every((r) => r.url.host == 'il.srgssr.ch'), isTrue);
      expect(log.first.url.path, startsWith('/integrationlayer/2.0/srf/'));
    });

    test('playback is never served from the cache', () async {
      final log = <http.Request>[];
      final provider = srfProvider(log: log);
      await provider.playback(_ref('video:$srfTagesschauVideo'));
      await provider.playback(_ref('video:$srfTagesschauVideo'));
      expect(log, hasLength(2));
    });
  });
}
