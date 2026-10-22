import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_api.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_ids.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_images.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_mapper.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_numbering.dart';
import 'package:plezy/replay/providers/nhkworld/nhkworld_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/nhkworld';
const _prefix = '/showsapi/v1/en/';
final _now = DateTime.utc(2026, 10, 22, 6);

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _items(String name) => (_json(name)['items'] as List).cast<Map<String, dynamic>>();

/// Every recorded episode, by id, so a lookup by id can be answered from any fixture.
Map<String, Map<String, dynamic>> _episodesById() => {
  for (final file in [
    'episodes_latest',
    'episodes_trending',
    'episodes_japanologyplus',
    'episodes_ah_neo',
    'category_episodes',
    'episode_legacy_host',
    'episode_with_captions',
  ])
    for (final item in _items(file)) item['id'] as String: item,
};

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(Iterable<Map<String, dynamic>> items) => {
  'pagination': {'limit': 100, 'offset': 0, 'count': items.length, 'total': items.length, 'next': null},
  'items': items.toList(),
};

/// Serves recorded NHK responses by path. [overrides] replaces episodes found by id.
http.Response Function(http.Request) _route(Map<String, Map<String, dynamic>> overrides) {
  final episodes = {..._episodesById(), ...overrides};
  final clips = {for (final c in _items('clips')) c['id'] as String: c};
  return (request) {
    final path = request.url.path.replaceFirst(_prefix, '');
    final query = request.url.queryParameters;
    final id = query['ids'];
    if (id == '429') {
      return http.Response('{}', 429, headers: {'retry-after': '30'});
    }
    return switch (path) {
      'categories/' => _ok(_json('categories')),
      'video_programs' => _ok(_json('programmes')),
      'categories/30/video_programs' => _ok(_json('category_programs')),
      'categories/30/video_episodes' => _ok(_json('category_episodes')),
      'video_episodes' when id != null => _ok(_page([?episodes[id]])),
      'video_episodes' => _ok(_json(query['sort'] == 'trending' ? 'episodes_trending' : 'episodes_latest')),
      'video_clips' when id != null => _ok(_page([?clips[id]])),
      'video_clips' => _ok(_json('clips')),
      'video_programs/japanologyplus' => _ok(_json('program_japanologyplus')),
      'video_programs/japanologyplus/video_episodes' => _ok(_json('episodes_japanologyplus')),
      'video_programs/ah-neo' => _ok(_json('program_ah_neo')),
      'video_programs/ah-neo/video_episodes' => _ok(_json('episodes_ah_neo')),
      _ when path.endsWith('/video_episodes') || path.endsWith('/video_programs') => _ok(_page(const [])),
      _ => http.Response('{"message":"Resource does not exist"}', 404, headers: {'content-type': 'application/json'}),
    };
  };
}

NhkWorldProvider _provider({Map<String, Map<String, dynamic>> overrides = const {}}) {
  final route = _route(overrides);
  final client = MediaServerHttpClient(client: MockClient((r) async => route(r)));
  return NhkWorldProvider.withApi(NhkWorldApi(client, clock: () => _now), clock: () => _now);
}

ReplayRef _ref(String nativeId) => ReplayRef('nhkworld', nativeId);

/// An episode from the fixtures with its `video` block changed.
Map<String, Map<String, dynamic>> _withVideo(String id, Map<String, Object?> changes) {
  final item = _episodesById()[id]!;
  return {
    id: {
      ...item,
      'video': {...(item['video'] as Map<String, dynamic>), ...changes},
    },
  };
}

Map<String, dynamic> _episode(String id, String aired) => {'id': id, 'first_broadcasted_at': aired};

void main() {
  group('NHK WORLD browsing', () {
    test('categories leave out those with no episode', () async {
      final categories = await _provider().categories();
      expect(categories.map((c) => c.id), containsAll(['20', '15', '30']));
      expect(categories.map((c) => c.id), isNot(contains('13')));
      expect(categories.firstWhere((c) => c.id == '30').title, 'Kids');
    });

    test('home offers latest, trending and clips', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.id), ['latest', 'trending', 'clips']);
      expect(rails.first.titles.first.title, 'Natto');
      expect(rails.last.titles.every((t) => t.kind == ReplayKind.clip), isTrue);
      expect(rails.expand((r) => r.titles).every((t) => t.ref.source == 'nhkworld'), isTrue);
    });

    test('an episode in a list carries the date its stream expires', () async {
      final natto = (await _provider().home()).first.titles.first;
      expect(natto.availableUntil, DateTime.utc(2026, 10, 29, 2, 58));
      expect(natto.availability, ReplayAvailability.playable);
    });

    test('a category page shows its programmes then its latest episodes', () async {
      final rails = await _provider().category('30');
      expect(rails.map((r) => r.id), ['programmes', 'latest']);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(rails.first.moreBrowseId, isNull);
    });

    test('the full listing hides programmes with nothing to watch', () async {
      final page = await _provider().listing(replayAllBrowseId);
      expect(page.totalCount, 7);
      expect(page.titles.map((t) => t.title).first, 'Core Kyoto');
      expect(page.titles.map((t) => t.ref.nativeId), isNot(contains('p/10yearshayaomiyazaki')));
      expect(page.titles.map((t) => t.ref.nativeId), isNot(contains('p/easyjapanese')));
    });

    test('a listing past the last page is empty but keeps the total', () async {
      final page = await _provider().listing(replayAllBrowseId, page: 3);
      expect(page.titles, isEmpty);
      expect(page.totalCount, 7);
    });

    test('a category listing holds only its programmes with episodes', () async {
      final page = await _provider().listing('30');
      expect(page.titles.map((t) => t.ref.nativeId), ['p/iwatagrandma', 'p/ah-neo']);
    });

    test('an unknown category lists nothing', () async {
      expect((await _provider().listing('999')).totalCount, 0);
    });
  });

  group('NHK WORLD search', () {
    test('every word must appear in the title, in any case', () async {
      final hits = await _provider().search('JAPAN delish');
      expect(hits.map((t) => t.ref.nativeId), ['p/japan-delish']);
    });

    test('title matches come before synopsis matches', () async {
      final hits = await _provider().search('japan');
      expect(hits.first.title, 'JAPAN DELISH');
      expect(hits.map((t) => t.ref.nativeId), contains('p/japanologyplus'));
    });

    test('a word in the synopsis finds the programme', () async {
      final hits = await _provider().search('peter barakan');
      expect(hits.map((t) => t.ref.nativeId), ['p/japanologyplus']);
    });

    test('blank, unknown and hidden programmes give nothing', () async {
      final provider = _provider();
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('miyazaki'), isEmpty);
    });
  });

  group('NHK WORLD shows', () {
    test('a show carries portrait art, a wide backdrop and its logo', () async {
      final show = (await _provider().title(_ref('p/japanologyplus')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.posterUrl, startsWith('https://www3.nhk.or.jp/nhkworld/en/shows/japanologyplus/images/portrait_m_'));
      expect(show.backdropUrl, contains('/wide_l_'));
      expect(show.logoUrl, endsWith('.png'));
      expect(show.genres, ['Culture & Lifestyle', 'Documentary']);
    });

    test('seasons are the years of first broadcast, oldest first', () async {
      final seasons = await _provider().children(_ref('p/japanologyplus'));
      expect(seasons.map((s) => s.seasonNumber), [2024, 2025, 2026]);
      expect(seasons.map((s) => s.childCount), [1, 6, 4]);
      expect(seasons.map((s) => s.ref.nativeId), [
        'p/japanologyplus/2024',
        'p/japanologyplus/2025',
        'p/japanologyplus/2026',
      ]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('p/japanologyplus')), isTrue);
    });

    test('a year mixing id families is numbered by broadcast date', () async {
      final episodes = await _provider().children(_ref('p/japanologyplus/2025'));
      expect(episodes.map((e) => e.ref.nativeId), [
        'e/5107009',
        'e/2032347',
        'e/2032348',
        'e/2032349',
        'e/2032350',
        'e/2032351',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      expect(episodes.first.title, 'Natto');
      expect(episodes.every((e) => e.seasonNumber == 2025), isTrue);
    });

    test('the same mix in 2026 keeps broadcast order, not id order', () async {
      final episodes = await _provider().children(_ref('p/japanologyplus/2026'));
      expect(episodes.map((e) => e.title), ['Solo-katsu', 'Eggs', 'Kutani Ware', 'Secondhand Goods']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
    });

    test('a year with one id family keeps NHK running numbers', () async {
      final episodes = await _provider().children(_ref('p/japanologyplus/2024'));
      expect(episodes.single.episodeNumber, 313);
    });

    test('an episode knows its show, season and number', () async {
      final natto = (await _provider().title(_ref('e/5107009')))!;
      expect(natto.kind, ReplayKind.episode);
      expect(natto.showRef, _ref('p/japanologyplus'));
      expect(natto.showTitle, 'Japanology Plus');
      expect(natto.seasonRef, _ref('p/japanologyplus/2025'));
      expect([natto.seasonNumber, natto.episodeNumber], [2025, 1]);
      expect(natto.durationSeconds, 1680);
      expect(natto.airDate, DateTime.utc(2025, 6, 5, 2, 30));
      expect(natto.summary, startsWith('With its unique smell'));
      expect(natto.backdropUrl, startsWith('https://www3.nhk.or.jp/nhkworld/en/shows/5107009/images/wide_m_'));
    });

    test('an episode without a title takes its programme title', () async {
      final legacy = (await _provider().title(_ref('e/3026036')))!;
      expect(legacy.title, startsWith('STATELESS'));
      expect(legacy.episodeNumber, 36);
      expect(legacy.availableUntil, DateTime.utc(2027, 8, 1, 14, 59));
    });

    test('a season ref resolves to its season', () async {
      final season = (await _provider().title(_ref('p/japanologyplus/2026')))!;
      expect(season.kind, ReplayKind.season);
      expect(season.childCount, 4);
    });

    test('unknown shows and episodes are absent, not errors', () async {
      final provider = _provider();
      expect(await provider.title(_ref('p/nothing')), isNull);
      expect(await provider.children(_ref('p/nothing')), isEmpty);
      expect(await provider.title(_ref('e/1234567')), isNull);
      expect(await provider.title(_ref('garbage')), isNull);
    });

    test('a clip is a clip with no season', () async {
      final clip = (await _provider().title(_ref('c/99990li')))!;
      expect(clip.kind, ReplayKind.clip);
      expect(clip.showRef, _ref('p/journeys'));
      expect(clip.seasonRef, isNull);
      expect(clip.durationSeconds, 30);
    });
  });

  group('NHK WORLD numbering', () {
    test('one family with distinct numbers uses the official ones', () {
      final numbered = nhkNumberSeason([
        _episode('2032352', '2026-01-08T02:30:00Z'),
        _episode('2032350', '2026-01-22T02:30:00Z'),
        _episode('2032351', '2026-01-15T02:30:00Z'),
      ]);
      expect(numbered.map((e) => e.number), [350, 351, 352]);
      expect(numbered.map((e) => e.item['id']), ['2032350', '2032351', '2032352']);
    });

    test('a repeated number sends the season to date order', () {
      final numbered = nhkNumberSeason([
        _episode('2032352', '2026-01-22T02:30:00Z'),
        _episode('2032352', '2026-01-08T02:30:00Z'),
      ]);
      expect(numbered.map((e) => e.number), [1, 2]);
      expect(numbered.first.item['first_broadcasted_at'], '2026-01-08T02:30:00Z');
    });

    test('an id of another shape sends the season to date order', () {
      final numbered = nhkNumberSeason([
        _episode('abc', '2026-02-01T00:00:00Z'),
        _episode('2032350', '2026-01-01T00:00:00Z'),
      ]);
      expect(numbered.map((e) => e.item['id']), ['2032350', 'abc']);
    });

    test('ids ending in 000 carry no official number', () {
      expect(nhkOfficialNumber('5107000'), isNull);
      expect(nhkOfficialNumber('99990li'), isNull);
      expect(nhkOfficialNumber('5107009'), 9);
    });

    test('an item with no date falls into the year of today', () {
      expect(nhkSeasonYear({'id': '1'}, _now), 2026);
      expect(
        nhkSeasonYear({
          'video': {'published_at': '2024-03-01T00:00:00Z'},
        }, _now),
        2024,
      );
    });

    test('the first broadcast line is dropped from a synopsis', () {
      expect(nhkSummary({'description': '*First broadcast on June 5, 2025\nFresh insights.'}), 'Fresh insights.');
      expect(nhkSummary({'description': '*First broadcast on June 5, 2025'}), isNull);
      expect(nhkSummary({'description': null}), isNull);
    });
  });

  group('NHK WORLD playback', () {
    test('a current episode yields its HLS master', () async {
      final playback = await _provider().playback(_ref('e/5107009'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'masterpl.hls.nhkworld.jp');
      expect(playback.streams.single.url.path, endsWith('/master.m3u8'));
    });

    test('an older episode on the legacy host plays too', () async {
      final playback = await _provider().playback(_ref('e/3026036'));
      expect(playback.streams.single.url.host, 'vod.nhkworld.jp');
    });

    test('a clip plays from its own host', () async {
      final playback = await _provider().playback(_ref('c/99990li'));
      expect(playback.streams.single.url.host, 'vod-stream.nhk.jp');
    });

    test('an episode past its expiry is reported as expired', () async {
      final overrides = _withVideo('5107009', {'expired_at': '2026-10-22T05:00:00Z'});
      final playback = await _provider(overrides: overrides).playback(_ref('e/5107009'));
      expect(playback.availability, ReplayAvailability.expired);
      expect(playback.streams, isEmpty);
      expect(playback.message, isNotEmpty);
    });

    test('an episode with no stream address is reported as expired', () async {
      final playback = await _provider(overrides: _withVideo('5107009', {'url': null})).playback(_ref('e/5107009'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('an episode not yet published is upcoming', () async {
      final overrides = _withVideo('5107009', {'url': null, 'published_at': '2026-10-23T02:00:00Z'});
      final playback = await _provider(overrides: overrides).playback(_ref('e/5107009'));
      expect(playback.availability, ReplayAvailability.upcoming);
    });

    test('the list marks an expired episode so it can be greyed out', () async {
      final overrides = _withVideo('5107009', {'expired_at': '2026-10-22T05:00:00Z'});
      final natto = (await _provider(overrides: overrides).title(_ref('e/5107009')))!;
      expect(natto.availability, ReplayAvailability.expired);
    });

    test('an episode the catalogue no longer lists is expired', () async {
      expect((await _provider().playback(_ref('e/1234567'))).availability, ReplayAvailability.expired);
    });

    test('shows, seasons and malformed ids are never played', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('p/japanologyplus'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('p/japanologyplus/2025'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('nonsense'))).availability, ReplayAvailability.unknown);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _provider().playback(_ref('e/429'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });
  });

  group('NHK WORLD artwork and ids', () {
    const images = [
      {'url': '/nhkworld/a_s.jpg', 'width': 320, 'height': 180},
      {'url': '/nhkworld/a_l.jpg', 'width': 1536, 'height': 864},
      {'url': '/nhkworld/a_m.jpg', 'width': 768, 'height': 432},
    ];

    test('the smallest image wide enough is picked, else the widest', () {
      expect(nhkPickImage(images, minWidth: 700), 'https://www3.nhk.or.jp/nhkworld/a_m.jpg');
      expect(nhkPickImage(images, minWidth: 5000), 'https://www3.nhk.or.jp/nhkworld/a_l.jpg');
      expect(nhkPickImage(images, minWidth: 1), 'https://www3.nhk.or.jp/nhkworld/a_s.jpg');
      expect(nhkPickImage(const [], minWidth: 1), isNull);
      expect(nhkPickImage(null, minWidth: 1), isNull);
    });

    test('references are fetchable as they are and owned by the provider', () {
      final provider = _provider();
      const url = 'https://www3.nhk.or.jp/nhkworld/a_m.jpg';
      expect(provider.imageUrl(url, width: 300, height: 170), url);
      expect(provider.imageUrl('/nhkworld/a_m.jpg'), url);
      expect(provider.ownsImage(url), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
    });

    test('native ids round trip through their parser', () {
      final target = parseNhkNativeId('p/japanologyplus/2025')!;
      expect([target.kind, target.id, target.year], [NhkTargetKind.season, 'japanologyplus', 2025]);
      expect(parseNhkNativeId(nhkEpisodeRef('5107009').nativeId)!.kind, NhkTargetKind.episode);
      expect(parseNhkNativeId(nhkClipRef('99990li').nativeId)!.kind, NhkTargetKind.clip);
      expect(parseNhkNativeId('p/x/year'), isNull);
      expect(parseNhkNativeId('p//2025'), isNull);
      expect(ReplayRef.tryParse('nhkworld:p/japanologyplus'), nhkShowRef('japanologyplus'));
    });

    test('the source is declared as clear English playback', () {
      final source = _provider().source;
      expect([source.id, source.language, source.support], ['nhkworld', 'en', ReplayPlaybackSupport.clear]);
    });
  });
}
