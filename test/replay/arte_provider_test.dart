import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/arte/arte_api.dart';
import 'package:plezy/replay/providers/arte/arte_images.dart';
import 'package:plezy/replay/providers/arte/arte_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/arte';

String _fixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

/// Serves recorded ARTE responses by URL path; anything else is an empty page.
http.Response _route(http.Request request) {
  final path = request.url.path;
  final routes = <String, String>{
    '/api/emac/v4/fr/web/pages/HOME/': 'home',
    '/api/emac/v4/fr/web/pages/SER': 'category',
    '/api/emac/v4/fr/web/pages/SES': 'subcategory_page',
    '/api/emac/v4/fr/web/pages/SEARCH': request.url.queryParameters['query'] == 'zzzz' ? 'search_empty' : 'search_page',
    '/api/emac/v4/fr/web/collections/RC-027942': 'collection_series_multiseason',
    '/api/emac/v4/fr/web/collections/RC-014077': 'collection_magazine',
    '/api/emac/v4/fr/web/collections/RC-027461': 'collection_miniseries_no_season',
    '/api/emac/v4/fr/web/programs/119364-001-A': 'program',
    '/api/player/v2/config/fr/119364-001-A': 'player_config',
    '/api/player/v2/config/fr/109316-000-F': 'player_config_geoblocked_be',
    '/api/player/v2/config/fr/132067-000-A': 'player_config_age16_timeslot',
    '/api/player/v2/config/fr/062925-000-A': 'player_config_no_rights_lang_en',
    '/api/player/v2/config/fr/105455-015-A': 'player_config_multi_stream',
  };
  final name = routes[path];
  if (name != null) return http.Response(_fixture(name), 200, headers: {'content-type': 'application/json'});
  if (path.contains('/zones/')) {
    return http.Response('{"data":[],"pagination":null}', 200, headers: {'content-type': 'application/json'});
  }
  if (path.endsWith('/config/fr/429')) return http.Response('429', 429, headers: {'retry-after': '30'});
  return http.Response('{}', 404);
}

ArteProvider _provider() {
  final client = MediaServerHttpClient(client: MockClient((r) async => _route(r)));
  return ArteProvider.withApi(ArteApi(client));
}

ReplayRef _ref(String id) => ReplayRef('arte', id);

void main() {
  group('ArteProvider browsing', () {
    test('home keeps only rows that have playable cards', () async {
      final rails = await _provider().home();
      expect(rails, isNotEmpty);
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.id);
        expect(rail.titles.every((t) => t.ref.source == 'arte'), isTrue);
      }
    });

    test('category page maps series to shows and videos to playable titles', () async {
      final rails = await _provider().category('SER');
      final titles = [for (final r in rails) ...r.titles];
      expect(titles.where((t) => t.kind == ReplayKind.show), isNotEmpty);
      expect(titles.where((t) => t.kind != ReplayKind.show).every((t) => t.isPlayable), isTrue);
    });

    test('series listing reports total count and first page', () async {
      final page = await _provider().listing(replayAllBrowseId);
      expect(page.totalCount, 57);
      expect(page.titles, isNotEmpty);
    });

    test('search returns cards, and an empty query returns nothing', () async {
      final provider = _provider();
      expect(await provider.search('nature'), isNotEmpty);
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
    });
  });

  group('ArteProvider shows', () {
    test('a series lists its seasons in order with their episode counts', () async {
      final seasons = await _provider().children(_ref('RC-027942'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      expect(seasons.map((s) => s.childCount), [6, 10, 10]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('RC-027942')), isTrue);
    });

    test('a season lists its episodes with numbers and parents', () async {
      final provider = _provider();
      final season = (await provider.children(_ref('RC-027942'))).first;
      final episodes = await provider.children(season.ref);
      expect(episodes, isNotEmpty);
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.episodeNumber, 1);
      expect(episodes.first.seasonNumber, 1);
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.showTitle, 'Please Like Me');
    });

    test('a magazine has one synthetic season holding every video', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('RC-014077'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref.nativeId, endsWith('/_all'));
      expect(await provider.children(seasons.single.ref), isNotEmpty);
    });

    test('a mini-series with one sub-collection is a single season', () async {
      final seasons = await _provider().children(_ref('RC-027461'));
      expect(seasons, hasLength(1));
      expect(seasons.single.seasonNumber, 1);
    });

    test('an episode page knows its show and season', () async {
      final episode = await _provider().title(_ref('119364-001-A'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('RC-027461'));
      expect(episode.seasonRef, _ref('RC-027461/RC-027462'));
      expect(episode.summary, isNot(contains('<')));
    });
  });

  group('ArteProvider playback', () {
    test('a playable program yields its HLS master and credits marker', () async {
      final playback = await _provider().playback(_ref('119364-001-A'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'manifest-arte.akamaized.net');
      expect(playback.streams.single.label, contains('VF'));
      expect(playback.credits?.start, const Duration(seconds: 3975));
    });

    test('a program with several versions offers each stream', () async {
      final playback = await _provider().playback(_ref('105455-015-A'));
      expect(playback.streams, hasLength(4));
    });

    test('geoblocked, restricted and expired programs say why', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('109316-000-F'))).availability, ReplayAvailability.geoBlocked);
      expect((await provider.playback(_ref('132067-000-A'))).availability, ReplayAvailability.timeSlotRestricted);
      expect((await provider.playback(_ref('062925-000-A'))).availability, ReplayAvailability.expired);
    });

    test('a missing program is reported as expired, not as an error', () async {
      expect((await _provider().playback(_ref('000000-000-A'))).availability, ReplayAvailability.expired);
    });

    test('a collection is never played directly', () async {
      expect((await _provider().playback(_ref('RC-027942'))).isPlayable, isFalse);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _provider().playback(_ref('429'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });
  });

  group('ARTE images', () {
    test('landscape and portrait boxes use sizes the resizer accepts', () {
      const template = 'https://api-cdn.arte.tv/img/v2/image/abc/__SIZE__';
      expect(arteImageUrl(template, width: 300, height: 170), endsWith('/340x192'));
      expect(arteImageUrl(template, width: 300, height: 450), endsWith('/300x450'));
      expect(arteImageUrl(template, width: 5000, height: 2000), endsWith('/1920x1080'));
      expect(arteImageUrl('$template?type=TEXT'), endsWith('/720x405?type=TEXT'));
      expect(
        arteImageUrl('$template?imageType=graphical_title', width: 300, height: 170),
        endsWith('/340x192.png?imageType=graphical_title'),
      );
    });
  });

  test('a native id containing a colon survives a ref round trip', () {
    final ref = ReplayRef.tryParse('arte:RC-1:RC-2');
    expect(ref, ReplayRef('arte', 'RC-1:RC-2'));
    expect(ReplayRef.tryParse(ref.toString()), ref);
    expect(jsonEncode(ReplayRef.tryParse('nothing')), 'null');
  });
}
