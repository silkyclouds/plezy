import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rtsplay/rtsplay_images.dart';
import 'package:plezy/replay/providers/rtsplay/rtsplay_provider.dart';
import 'package:plezy/replay/providers/rtsplay/rtsplay_unit.dart';
import 'package:plezy/replay/providers/srg/srg_api.dart';
import 'package:plezy/replay/providers/srg/srg_ids.dart';
import 'package:plezy/replay/providers/srg/srg_mapper.dart';
import 'package:plezy/replay/providers/srg/srg_numbering.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/rtsplay';
final _mapper = SrgMapper(rtsPlayUnit);
const _clearId = '9a456c6b-899e-321a-8589-dc41eb60fcad';
const _drmId = '77664424-7f00-3e17-977e-9887e03ab687';
const _geoId = '0d9865f7-9973-3886-b61c-89a5a98c430e';

String _fixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

http.Response _json(String body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json', ...headers});

const _emptyLists = '{"mediaList":[],"showList":[],"searchResultMediaList":[],"searchResultShowList":[]}';

/// A video as the lists describe it, with only the fields the provider reads.
Map<String, dynamic> _video(
  String id,
  String date, {
  String show = 'daily',
  int count = 450,
  String type = 'EPISODE',
}) => {
  'id': id,
  'urn': 'urn:rts:video:$id',
  'mediaType': 'VIDEO',
  'type': type,
  'title': 'Journal $id',
  'date': date,
  'duration': 600000,
  'validTo': '2100-01-01T23:59:59+01:00',
  'playableAbroad': true,
  'show': {'id': show, 'title': 'Journal', 'numberOfEpisodes': count},
};

/// A daily programme with [total] episodes, one per day counting back from 2026-10-20, served 100 per page.
http.Response _dailyPage(int index, int total) {
  final start = DateTime.utc(2026, 10, 20);
  final items = [
    for (var n = index * 100; n < total && n < index * 100 + 100; n++)
      _video(
        'd$n',
        '${start.subtract(Duration(days: n)).toIso8601String().substring(0, 10)}T19:30:00+02:00',
        count: total,
      ),
  ];
  final next = (index + 1) * 100 < total
      ? 'https://il.srgssr.ch/integrationlayer/2.0/rts/mediaList/video/latest/byShow/daily?pageSize=100&next=${index + 1}'
      : null;
  return _json(jsonEncode({'next': ?next, 'mediaList': items}));
}

String _composition({
  String? blockReason,
  List<Map<String, dynamic>>? resources,
  String validTo = '2100-01-01T23:59:59+01:00',
}) {
  return jsonEncode({
    'chapterList': [
      {
        'id': 'x1',
        'urn': 'urn:rts:video:x1',
        'mediaType': 'VIDEO',
        'type': 'EPISODE',
        'title': 'Un film',
        'validTo': validTo,
        'blockReason': ?blockReason,
        'resourceList': ?resources,
      },
    ],
  });
}

Map<String, dynamic> _resource(String streaming, String url, {List<Map<String, String>>? drm}) => {
  'url': url,
  'streaming': streaming,
  'drmList': ?drm,
  'audioTrackList': [
    {'locale': 'fr'},
  ],
};

http.Response _lists(String path, Map<String, String> q) {
  if (path.startsWith('section/')) {
    return _json(switch (path.split('/').last) {
      'bccb1204-611a-43ed-9216-8413ee7f06f8' => _fixture('section_shows_with_empty'),
      'b30d5230-61f5-41c7-8c3d-660846739eaa' => _fixture('section_shows'),
      'd6415174-9679-46a6-bc02-4e73567b562d' => _fixture('section_media_with_show'),
      '30167d0c-063b-4bdb-ac3b-69381871a5d2' => _fixture('section_media'),
      _ => _emptyLists,
    });
  }
  return switch (path) {
    'topicList/tv' => _json(_fixture('topics')),
    'page/byTopicUrn/urn:rts:topic:tv:2743' => _json(_fixture('topic_page')),
    'mediaList/video/trending' => _json(_fixture('trending')),
    'mediaList/video/latestEpisodes' => _json(_fixture('latest_episodes')),
    'showList/tv/alphabetical' => _json(_fixture(q['next'] == '1' ? 'shows_page1' : 'shows_page0')),
    _ => _json(_emptyLists),
  };
}

http.Response _search(String path, Map<String, String> q) {
  final text = q['q'];
  if (path == 'searchResultShowList') {
    return _json(switch (text) {
      'bye' => _fixture('search_shows'),
      '19h30' => _fixture('search_shows_signed'),
      _ => _emptyLists,
    });
  }
  if (q['showUrns'] == 'urn:rts:show:tv:capped') {
    final from = int.parse(q['next'] ?? '0');
    final count = from == 0 ? 100 : 20;
    final items = [
      for (var n = 0; n < count; n++) _video('c${from + n}', '2026-01-01T10:00:00+01:00', show: 'capped', count: 120),
      if (from > 0) _video('clip1', '2026-01-01T10:00:00+01:00', show: 'capped', count: 120, type: 'CLIP'),
    ];
    return _json(jsonEncode({'total': 120, 'searchResultMediaList': items}));
  }
  return _json(switch (text) {
    'bye' => _fixture('search_media_bye'),
    'radio' => jsonEncode({
      'searchResultMediaList': [
        {'id': 'a1', 'urn': 'urn:rts:audio:a1', 'mediaType': 'AUDIO', 'type': 'EPISODE', 'title': 'Radio'},
        ...(jsonDecode(_fixture('search_media_bye'))['searchResultMediaList'] as List).take(1),
      ],
    }),
    _ => _emptyLists,
  });
}

http.Response _shows(String path) {
  final id = path.split('/').last;
  if (path.startsWith('show/tv/')) {
    final body = switch (id) {
      '5921007' => _fixture('show_bye_bye'),
      '14979947' => _fixture('show_cats_eyes'),
      'daily' => jsonEncode({'id': 'daily', 'title': 'Journal', 'numberOfEpisodes': 450}),
      'capped' => jsonEncode({'id': 'capped', 'title': 'Capped', 'numberOfEpisodes': 120}),
      'plain' => jsonEncode({'id': 'plain', 'title': 'Magazine', 'numberOfEpisodes': 4}),
      _ => null,
    };
    return body == null ? _json('{"status":404}', 404) : _json(body);
  }
  return switch (id) {
    '5921007' => _json(_fixture('episodes_bye_bye')),
    '14979947' => _json(_fixture('episodes_cats_eyes')),
    'capped' => _json(
      jsonEncode({
        'mediaList': [
          for (var n = 0; n < 100; n++) _video('c$n', '2026-01-01T10:00:00+01:00', show: 'capped', count: 120),
        ],
      }),
    ),
    'plain' => _json(
      jsonEncode({
        'mediaList': [
          for (var n = 1; n <= 4; n++) _video('p$n', '2026-03-0${n}T10:00:00+01:00', show: 'plain', count: 4),
        ],
      }),
    ),
    _ => _json(_emptyLists),
  };
}

http.Response _playback(String id) {
  final resource = [_resource('HLS', 'https://cdn.example/ww/x/master.m3u8')];
  final drm = [
    _resource(
      'HLS',
      'https://rtsvod-drm-g.akamaized.net/a/index.m3u8',
      drm: [
        {'type': 'FAIRPLAY'},
      ],
    ),
  ];
  return switch (id) {
    _clearId => _json(_fixture('media_composition_clear')),
    _drmId => _json(_fixture('media_composition_drm')),
    _geoId => _json(_fixture('media_composition_geoblocked')),
    'expired' => _json(_composition(validTo: '2020-01-01T00:00:00+01:00')),
    'ended' => _json(_composition(blockReason: 'ENDDATE')),
    'upcoming' => _json(_composition(blockReason: 'STARTDATE')),
    'vpn' => _json(_composition(blockReason: 'VPNORPROXYDETECTED')),
    'age' => _json(_composition(blockReason: 'AGERATING18')),
    'empty' => _json(_composition()),
    'mixed' => _json(_composition(resources: [...drm, _resource('PROGRESSIVE', 'https://cdn.example/a.mp4')])),
    'protected-host' => _json(
      _composition(resources: [_resource('HLS', 'https://rtsvod-drm-g.akamaized.net/a/index.m3u8')]),
    ),
    'protected-only' => _json(_composition(resources: drm)),
    'live' => _json(
      _composition(
        resources: [
          {..._resource('HLS', 'https://cdn.example/live.m3u8'), 'live': true},
        ],
      ),
    ),
    'mp4' => _json(_composition(resources: [_resource('PROGRESSIVE', 'https://cdn.example/a.mp4')])),
    'limited' => _json('{}', 429, {'retry-after': '30'}),
    'clear' => _json(_composition(resources: resource)),
    _ => _json('{"status":404}', 404),
  };
}

/// Serves recorded Integration Layer responses by path; anything unknown is an empty list or a 404.
http.Response _route(http.Request request) {
  final path = request.url.path.replaceFirst('/integrationlayer/2.0/', '');
  final q = request.url.queryParameters;
  if (path.startsWith('mediaComposition/byUrn/urn:rts:video:')) {
    return _playback(path.split(':').last);
  }
  if (path.startsWith('rts/searchResult')) return _search(path.substring(4), q);
  final unit = path.replaceFirst('rts/', '');
  if (unit.startsWith('show/tv/')) return _shows(unit);
  if (unit.startsWith('mediaList/video/latest/byShow/')) {
    final id = unit.split('/').last;
    if (id == 'daily') return _dailyPage(int.parse(q['next'] ?? '0'), 450);
    return _shows(unit);
  }
  return _lists(unit, q);
}

RtsPlayProvider _provider({List<http.Request>? log, http.Response Function(http.Request)? route}) {
  final client = MediaServerHttpClient(
    client: MockClient((request) async {
      log?.add(request);
      return (route ?? _route)(request);
    }),
  );
  return RtsPlayProvider.withApi(SrgApi(rtsPlayUnit, client));
}

ReplayRef _ref(String native) => ReplayRef('rtsplay', native);

void main() {
  group('RtsPlayProvider source', () {
    test('is a clear French source paged by hundreds', () {
      final source = _provider().source;
      expect((source.id, source.name, source.language), ('rtsplay', 'RTS Play', 'fr'));
      expect(source.support, ReplayPlaybackSupport.clear);
      expect(source.listingPageSize, 100);
    });
  });

  group('RtsPlayProvider browsing', () {
    test('categories are the topics of the TV catalogue', () async {
      final categories = await _provider().categories();
      expect(categories, hasLength(10));
      expect(categories.map((c) => c.title), containsAll(['Jeunesse', 'Documentaires']));
      expect(categories.every((c) => int.tryParse(c.id) != null), isTrue);
    });

    test('home rows drop blocked cards and empty rows', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.id), ['latest', 'trending']);
      final titles = [for (final r in rails) ...r.titles];
      expect(titles.every((t) => t.availability == ReplayAvailability.playable), isTrue);
      expect(rails.last.titles.first.kind, ReplayKind.clip);
      expect(rails.first.titles.first.showTitle, isNotNull);
    });

    test('a topic page keeps content rows and drops banners', () async {
      final rails = await _provider().category('2743');
      expect(rails.map((r) => r.title), ['Les trésors du moment', 'Vidéos les plus récentes']);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(rails.last.titles.map((t) => t.kind), [ReplayKind.episode, ReplayKind.clip, ReplayKind.clip]);
      expect(rails.last.moreBrowseId, startsWith('MediaSection/30167d0c'));
      expect(rails.first.moreBrowseId, isNull);
    });

    test('a category id that is not a topic number gives no rows', () async {
      final log = <http.Request>[];
      expect(await _provider(log: log).category('../x'), isEmpty);
      expect(log, isEmpty);
    });

    test('the catalogue listing merges pages and hides signed twins', () async {
      final provider = _provider();
      final page = await provider.listing(replayAllBrowseId);
      expect(page.totalCount, 5);
      expect(page.titles.map((t) => t.title), [
        '120 secondes',
        '12h45',
        '19h30',
        'À vrai dire',
        'Anatomía de un instante',
      ]);
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a show with a generic poster falls back to its landscape picture', () async {
      final page = await _provider().listing(replayAllBrowseId);
      final generic = page.titles.firstWhere((t) => t.title == 'À vrai dire');
      expect(generic.posterUrl, isNull);
      expect(generic.backdropUrl, startsWith('https://img.rts.ch/'));
      expect(page.titles.first.posterUrl, endsWith('/2x3'));
    });

    test('a row listing flags the videos blocked from this country', () async {
      final page = await _provider().listing('MediaSectionWithShow/d6415174-9679-46a6-bc02-4e73567b562d');
      expect(page.titles, hasLength(5));
      expect(page.titles.every((t) => t.availability == ReplayAvailability.geoBlocked), isTrue);
      expect(page.totalCount, 6);
    });

    test('an unknown listing id is empty', () async {
      expect((await _provider().listing('nonsense')).titles, isEmpty);
    });
  });

  group('RtsPlayProvider search', () {
    test('shows come first, then videos, without repeats', () async {
      final results = await _provider().search('bye');
      expect(results.take(2).map((t) => t.kind), [ReplayKind.show, ReplayKind.show]);
      expect(results.where((t) => t.kind != ReplayKind.show), hasLength(3));
      expect(results.map((t) => t.ref).toSet(), hasLength(results.length));
    });

    test('signed copies of a show are left out', () async {
      final shows = await _provider().search('19h30');
      expect(shows.map((t) => t.ref.nativeId), ['show:105932', 'show:2075878']);
    });

    test('audio results are dropped and a blank query asks nothing', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      final results = await provider.search('radio');
      expect(results.every((t) => t.ref.nativeId.startsWith('video:')), isTrue);
      expect(results.map((t) => t.title), isNot(contains('Radio')));
      log.clear();
      expect(await provider.search('   '), isEmpty);
      expect(log, isEmpty);
    });
  });

  group('RtsPlayProvider seasons', () {
    test('a numbered show lists its seasons, then its extras', () async {
      final seasons = await _provider().children(_ref('show:5921007'));
      expect(seasons.map((s) => s.seasonNumber), [1, 14, 15, 0]);
      expect(seasons.map((s) => s.title), ['Saison 1', 'Saison 14', 'Saison 15', 'Bonus']);
      expect(seasons.map((s) => s.childCount), [3, 3, 3, 3]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show:5921007')), isTrue);
    });

    test('a season lists its episodes in order with cleaned titles', () async {
      final provider = _provider();
      final season = (await provider.children(_ref('show:5921007'))).firstWhere((s) => s.seasonNumber == 15);
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [2, 3, 4]);
      expect(episodes.first.title, isNot(contains('Saison')));
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonNumber, 15);
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.showTitle, 'Bye bye la Suisse');
      expect(episodes.first.durationSeconds, greaterThan(2000));
    });

    test('extras next to real seasons are numbered zero and unnumbered', () async {
      final provider = _provider();
      final bonus = (await provider.children(_ref('show:5921007'))).last;
      final episodes = await provider.children(bonus.ref);
      expect(episodes, hasLength(3));
      expect(episodes.every((e) => e.episodeNumber == null && e.seasonNumber == 0), isTrue);
      expect(episodes.first.airDate!.isAfter(episodes.last.airDate!), isTrue);
    });

    test('episodes numbered without a season form season one', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('show:14979947'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 0]);
      final first = await provider.children(seasons.first.ref);
      expect(first.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(first.first.title, 'Tamara (1/8)');
      expect(first.every((e) => e.seasonNumber == 1), isTrue);
    });

    test('a show with no numbers has one season named after it', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('show:plain'));
      expect(seasons, hasLength(1));
      expect((seasons.single.title, seasons.single.seasonNumber, seasons.single.childCount), ('Magazine', 1, 4));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.ref.nativeId), ['video:p4', 'video:p3', 'video:p2', 'video:p1']);
      expect(episodes.first.seasonNumber, 1);
    });

    test('episodes of a blocked show say so', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('show:14979947'));
      final episodes = await provider.children(seasons[1].ref);
      expect(episodes.every((e) => e.availability == ReplayAvailability.geoBlocked), isTrue);
    });

    test('a full page without continuation is read again by offset', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      final seasons = await provider.children(_ref('show:capped'));
      expect(seasons.single.childCount, 120);
      expect(log.where((r) => r.url.queryParameters['showUrns'] != null).map((r) => r.url.queryParameters['next']), [
        null,
        '100',
      ]);
    });

    test('a missing show has no children and no title', () async {
      final provider = _provider();
      expect(await provider.children(_ref('show:nope')), isEmpty);
      expect(await provider.title(_ref('show:nope')), isNull);
      expect(await provider.children(_ref('garbage')), isEmpty);
    });

    test('a show and a season resolve by reference', () async {
      final provider = _provider();
      final show = await provider.title(_ref('show:5921007'));
      expect((show!.kind, show.title), (ReplayKind.show, 'Bye bye la Suisse'));
      final season = await provider.title(_ref('season:5921007/s14'));
      expect((season!.kind, season.seasonNumber, season.showTitle), (ReplayKind.season, 14, 'Bye bye la Suisse'));
      expect(await provider.title(_ref('season:5921007/s99')), isNull);
    });
  });

  group('RtsPlayProvider long daily shows', () {
    test('seasons are the broadcast years, found without loading every page', () async {
      final log = <http.Request>[];
      final seasons = await _provider(log: log).children(_ref('show:daily'));
      expect(seasons.map((s) => s.title), ['2025', '2026']);
      expect(seasons.map((s) => s.seasonNumber), [2025, 2026]);
      expect(log.length, lessThan(15));
    });

    test('a year holds exactly the episodes aired that year, newest first', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('show:daily'));
      final y2025 = await provider.children(seasons.first.ref);
      final y2026 = await provider.children(seasons.last.ref);
      expect(y2026, hasLength(293));
      expect(y2025, hasLength(157));
      expect(y2025.every((e) => e.airDate!.year == 2025), isTrue);
      expect(y2026.first.airDate!.isAfter(y2026.last.airDate!), isTrue);
      expect(y2026.first.seasonRef, seasons.last.ref);
    });

    test('an unnumbered episode of a long show points at its year', () async {
      final composition = jsonDecode(_fixture('media_composition_clear')) as Map<String, dynamic>;
      final title = _mapper.fromComposition(composition);
      expect(title!.seasonRef, _ref('season:385418/y2026'));
      expect(title.showRef, _ref('show:385418'));
    });
  });

  group('RtsPlayProvider titles', () {
    test('an episode is read from its media composition', () async {
      final title = await _provider().title(_ref('video:$_clearId'));
      expect(title!.kind, ReplayKind.episode);
      expect(title.title, startsWith('Du poulet'));
      expect(title.showTitle, 'A bon entendeur');
      expect(title.genres, isEmpty);
      expect(title.availability, ReplayAvailability.playable);
      expect(title.availableUntil, isNull);
      expect(title.durationSeconds, 2273);
    });

    test('a film of an umbrella show is a movie without a parent', () {
      final film = {
        ..._video('film1', '2020-01-01T20:00:00+01:00', show: '1800017', count: 900),
        'episode': {'title': 'Telefilm'},
      };
      final title = _mapper.fromMedia(film)!;
      expect((title.kind, title.showRef, title.seasonRef), (ReplayKind.movie, null, null));
    });

    test('a blocked item in a list is flagged for this country', () async {
      final titles = (await _provider().listing('MediaSection/30167d0c-063b-4bdb-ac3b-69381871a5d2')).titles;
      expect(titles.map((t) => t.availability), [
        ReplayAvailability.playable,
        ReplayAvailability.playable,
        ReplayAvailability.playable,
        ReplayAvailability.geoBlocked,
        ReplayAvailability.geoBlocked,
        ReplayAvailability.geoBlocked,
      ]);
    });

    test('rights that ended or have not begun are predicted', () {
      final ended = {..._video('e1', '2020-01-01T20:00:00+01:00'), 'validTo': '2021-01-01T00:00:00+01:00'};
      final later = {..._video('e2', '2020-01-01T20:00:00+01:00'), 'validFrom': '2999-01-01T00:00:00+01:00'};
      expect(_mapper.fromMedia(ended)!.availability, ReplayAvailability.expired);
      expect(_mapper.fromMedia(later)!.availability, ReplayAvailability.upcoming);
    });

    test('audio and live items are not titles', () {
      expect(_mapper.fromMedia({'id': 'a', 'urn': 'urn:rts:audio:a', 'mediaType': 'AUDIO', 'type': 'EPISODE'}), isNull);
      expect(_mapper.fromMedia(_video('l1', '2026-01-01T00:00:00+01:00', type: 'LIVESTREAM')), isNull);
    });
  });

  group('RtsPlayProvider playback', () {
    test('a clear programme yields its HLS master', () async {
      final playback = await _provider().playback(_ref('video:$_clearId'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.toString(), endsWith('/master.m3u8'));
      expect(playback.streams.single.url.host, 'rts-vod-amd.akamaized.net');
      expect(playback.streams.single.label, 'VF');
      expect(playback.streams.single.headers, isEmpty);
    });

    test('a geoblocked programme says so', () async {
      final playback = await _provider().playback(_ref('video:$_geoId'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('a DRM programme is reported, never offered', () async {
      final playback = await _provider().playback(_ref('video:$_drmId'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('FAIRPLAY'));
    });

    test('a protected CDN host is DRM even without a scheme list', () async {
      final playback = await _provider().playback(_ref('video:protected-host'));
      expect(playback.isPlayable, isFalse);
    });

    test('a clear rendition wins over a protected one', () async {
      final playback = await _provider().playback(_ref('video:mixed'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('.mp4'));
      expect((await _provider().playback(_ref('video:protected-only'))).availability, ReplayAvailability.drmProtected);
    });

    test('block reasons map to their availability', () async {
      final provider = _provider();
      Future<ReplayAvailability> reason(String id) async => (await provider.playback(_ref('video:$id'))).availability;
      expect(await reason('vpn'), ReplayAvailability.geoBlocked);
      expect(await reason('upcoming'), ReplayAvailability.upcoming);
      expect(await reason('ended'), ReplayAvailability.expired);
      expect(await reason('expired'), ReplayAvailability.expired);
      expect(await reason('age'), ReplayAvailability.timeSlotRestricted);
    });

    test('a programme with no streams or only a live one is expired', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('video:empty'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('video:live'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('video:gone'))).availability, ReplayAvailability.expired);
    });

    test('shows and seasons are never played directly', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('show:5921007'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('season:5921007/s1'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('video:../x'))).isPlayable, isFalse);
    });

    test('rate limiting is reported and later calls wait', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      final first = await provider.playback(_ref('video:limited'));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));
      final before = log.length;
      expect((await provider.playback(_ref('video:$_clearId'))).message, contains('Rate limited'));
      expect(log.length, before);
    });
  });

  group('RtsPlayProvider requests', () {
    test('lists are cached and identify the app', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      await provider.home();
      final first = log.length;
      await provider.home();
      expect(log.length, first);
      expect(log.first.headers['User-Agent'], contains('Plezy-Replay'));
      expect(log.every((r) => r.url.host == 'il.srgssr.ch'), isTrue);
    });

    test('playback is never served from the cache', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      await provider.playback(_ref('video:$_clearId'));
      await provider.playback(_ref('video:$_clearId'));
      expect(log, hasLength(2));
    });
  });

  group('RTS Play numbering', () {
    SrgNumbers read(String title, {Map<String, dynamic>? episode}) =>
        rtsPlayUnit.numbering.numbers({'title': title, 'episode': ?episode});

    test('the structured fields win over the title', () {
      expect(read('Un titre (Episode 9 - Saison 9)', episode: {'seasonNumber': 2, 'number': 5}), (
        season: 2,
        episode: 5,
      ));
    });

    test('the label in the title gives both numbers', () {
      expect(read('Un chantier (Episode 4 - Saison 15)'), (season: 15, episode: 4));
      expect(read('Saison 3 Épisode 7'), (season: 3, episode: 7));
      expect(read('Série S02E10'), (season: 2, episode: 10));
    });

    test('an episode label alone gives only the episode', () {
      expect(read('Prudence (Episode 6)'), (season: null, episode: 6));
      expect(read('Tamara (1/8)'), (season: null, episode: null));
    });

    test('an API season is kept when the number comes from the title', () {
      expect(read('Pilote (Episode 3)', episode: {'seasonNumber': 4}), (season: 4, episode: 3));
    });

    test('zero and text are not numbers', () {
      expect(read('Rien', episode: {'seasonNumber': 0, 'number': 'x'}), (season: null, episode: null));
    });

    test('the label is removed from the displayed title only', () {
      expect(rtsPlayUnit.numbering.cleanTitle('Tamara (1/8) (Episode 1)'), 'Tamara (1/8)');
      expect(rtsPlayUnit.numbering.cleanTitle('Femmes-orchestres (Episode 6 - Saison 14)'), 'Femmes-orchestres');
      expect(rtsPlayUnit.numbering.cleanTitle('(Episode 2)'), '(Episode 2)');
    });
  });

  group('RTS Play artwork and ids', () {
    test('a picture keeps its crop and gets a width bucket', () {
      const base = 'https://img.rts.ch/medias/2026/image/abc-1.image';
      expect(rtsPlayImageUrl('$base/16x9', width: 300), '$base/16x9/scale/width/320');
      expect(rtsPlayImageUrl('$base/2x3', width: 300, height: 450), '$base/2x3/scale/width/320');
      expect(rtsPlayImageUrl('$base/16x9', width: 5000), '$base/16x9/scale/width/1920');
    });

    test('a bare picture takes its crop from the box', () {
      const base = 'https://img.rts.ch/articles/2023/image/x-1.image';
      expect(rtsPlayImageUrl(base, width: 448, height: 252), '$base/16x9/scale/width/448');
      expect(rtsPlayImageUrl(base, width: 300, height: 450), '$base/2x3/scale/width/320');
      expect(rtsPlayImageUrl(base), '$base/16x9/scale/width/640');
    });

    test('generic fallback pictures are used as given', () {
      const generic = 'https://il.srgssr.ch/image-service/dynamic/4d02e478.jpg';
      expect(rtsPlayImageUrl(generic, width: 300), generic);
      expect(_provider().ownsImage(generic), isTrue);
      expect(_provider().ownsImage('https://example.com/a.jpg'), isFalse);
    });

    test('a native id survives a round trip', () {
      for (final native in [
        'show:5921007',
        'show:5615b0e0-868b',
        'season:5921007/s14',
        'season:x/y2026',
        'season:x/other',
        'video:f40ea207-cd0e',
      ]) {
        final parsed = ReplayRef.tryParse('rtsplay:$native');
        expect(parsed, ReplayRef('rtsplay', native));
        expect(SrgId.tryParse(parsed!.nativeId), isNotNull, reason: native);
      }
      expect(SrgId.tryParse('video:a/b'), isNull);
      expect(SrgId.tryParse('season:x/z3'), isNull);
      expect(SrgId.tryParse('season:x'), isNull);
    });
  });
}
