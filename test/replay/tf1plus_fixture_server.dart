import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_api.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/tf1plus';
const _jsonHeaders = {'content-type': 'application/json'};

/// Video ids the media info route answers for, each tied to one recorded answer.
abstract final class Tf1TestVideo {
  static const loginRequired = '8a566929-5d1e-488f-b5f7-fc0256c77d8b';
  static const filmFranceOnly = '03a61d77-e78e-4b5a-b2ee-52b4c230a13a';
  static const geoBlockedClip = '04e214ba-bb49-4c35-9c4f-efcf85004107';
  static const widevine = '3cb64702-94af-4a13-9b02-4d27128d2cef';
  static const fairplay = '00000000-0000-4000-8000-0000000000f1';
  static const withoutDrm = '00000000-0000-4000-8000-0000000000c1';
  static const unknown = '00000000-0000-4000-8000-000000000000';
  static const notFoundStatus = '00000000-0000-4000-8000-0000000000e4';
  static const rateLimited = '00000000-0000-4000-8000-000000000429';
}

Map<String, dynamic> tf1Fixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Serves recorded TF1+ answers by operation id and variables, and remembers every request.
class Tf1FixtureServer {
  static const _heads = {
    'hpi': 'head_hpi',
    'aquaman': 'head_aquaman',
    'jt-20h': 'head_jt',
    'sept-a-huit': 'head_sept_a_huit',
    'les-anges': 'head_les_anges',
    'pyjamasques-power-heroes-le-cercle-des-heros': 'head_no_replay',
  };
  static const _details = {
    'hpi': 'detail_hpi',
    'aquaman': 'detail_aquaman',
    'jt-20h': 'detail_jt',
    'sept-a-huit': 'detail_sept_a_huit',
    'les-anges': 'detail_les_anges',
    'pyjamasques-power-heroes-le-cercle-des-heros': 'detail_no_replay',
  };
  static const _seasons = {
    '611169bd645161a2': 'season_hpi_2',
    '61c40f4139dfabcd': 'season_les_anges_asian_dream',
    'a3d81873e520131b': 'season_sept_a_huit_2025',
  };

  final List<Uri> requests = [];
  final Map<String, String> _detailBySlugId = {};

  Tf1FixtureServer() {
    _details.forEach((slug, detail) {
      final id = tf1Fixture(_heads[slug]!)['data']['programBySlug']['id'] as String;
      _detailBySlugId[id] = detail;
    });
  }

  MediaServerHttpClient get client => MediaServerHttpClient(client: MockClient((r) async => handle(r)));

  Tf1Api api({Tf1Pacing pacing = Tf1Pacing.none, Future<void> Function(Duration)? delay}) =>
      Tf1Api(client, pacing: pacing, delay: delay);

  Tf1PlusProvider provider() => Tf1PlusProvider.withApi(api());

  /// Requests that reached the catalogue gateways with the given persisted query id.
  List<Map<String, dynamic>> variablesOf(String operation) => [
    for (final uri in requests)
      if (uri.queryParameters['id'] == operation) jsonDecode(uri.queryParameters['variables']!) as Map<String, dynamic>,
  ];

  http.Response handle(http.Request request) {
    requests.add(request.url);
    if (request.url.host == 'mediainfo.tf1.fr') return _mediaInfo(request.url.pathSegments.last);
    final variables = jsonDecode(request.url.queryParameters['variables'] ?? '{}') as Map<String, dynamic>;
    return switch (request.url.queryParameters['id']) {
      Tf1Operation.programs => _programs(variables),
      Tf1Operation.programVideos => _videos(variables),
      Tf1Operation.programDetail => _detail(variables['programId'] as String),
      Tf1Operation.seasonEpisodes => _seasonEpisodes(variables),
      Tf1Operation.searchPrograms => _search(variables, 'search_programs', 'searchPrograms'),
      Tf1Operation.searchVideos => _search(variables, 'search_videos', 'searchVideos'),
      _ => http.Response('{"error":"no queries to execute"}', 400, headers: _jsonHeaders),
    };
  }

  http.Response _programs(Map<String, dynamic> variables) {
    final filter = variables['filter'] as Map<String, dynamic>;
    final name = switch (filter) {
      {'categorySlug': 'series'} => 'programs_series',
      {'categorySlug': 'films'} => 'programs_films',
      {'category': 'MAIN_ENTERTAINEMENT'} => 'programs_with_repeat',
      _ => null,
    };
    if (name == null || (variables['offset'] as int) > 0) {
      return _body({
        'data': {
          'programs': {'total': name == null ? 0 : tf1Fixture(name)['data']['programs']['total'], 'items': []},
        },
      });
    }
    return _file(name);
  }

  http.Response _videos(Map<String, dynamic> variables) {
    final slug = variables['programSlug'] as String;
    final type = (variables['types'] as List).single as String;
    if ((variables['offset'] as int) > 0) return _emptyVideos(slug);
    if (variables['limit'] == 1) {
      final head = _heads[slug];
      return head == null
          ? _body({
              'data': {'programBySlug': null},
            })
          : _file(head);
    }
    final name = switch ((slug, type)) {
      ('jt-20h', 'REPLAY') => 'videos_jt',
      ('pyjamasques-power-heroes-le-cercle-des-heros', 'REPLAY') => 'videos_replay_empty',
      ('pyjamasques-power-heroes-le-cercle-des-heros', 'EXTRACT') => 'videos_extract_empty',
      ('pyjamasques-power-heroes-le-cercle-des-heros', 'BONUS') => 'videos_bonus_no_replay',
      _ => null,
    };
    return name == null ? _emptyVideos(slug) : _file(name);
  }

  http.Response _emptyVideos(String slug) => _body({
    'data': {
      'programBySlug': {
        'id': slug,
        'videos': {'total': 0, 'items': []},
      },
    },
  });

  http.Response _detail(String programId) {
    final name = _detailBySlugId[programId];
    return name == null
        ? _body({
            'data': {'programById': null},
          })
        : _file(name);
  }

  http.Response _seasonEpisodes(Map<String, dynamic> variables) {
    final name = _seasons[variables['listId']];
    if (name == null || (variables['offset'] as int) > 0) {
      return _body({
        'data': {
          'programBySlug': {
            'editorialSections': [
              {'listById': null},
            ],
          },
        },
      });
    }
    return _file(name);
  }

  http.Response _search(Map<String, dynamic> variables, String fixture, String field) {
    if (variables['query'] == 'koh lanta') return _file(fixture);
    return _body({
      'data': {
        field: {'total': 0, 'items': []},
      },
    });
  }

  http.Response _mediaInfo(String videoId) => switch (videoId) {
    Tf1TestVideo.loginRequired => _file('mediainfo_denied_login'),
    Tf1TestVideo.filmFranceOnly => _file('mediainfo_denied_fr_only'),
    Tf1TestVideo.geoBlockedClip => _file('mediainfo_geoblocked'),
    Tf1TestVideo.widevine => _file('mediainfo_widevine'),
    Tf1TestVideo.fairplay => _file('mediainfo_fairplay'),
    Tf1TestVideo.withoutDrm => _body({
      'media': {'id': '1', 'title': 'Clip', 'programName': 'Show', 'programSlug': 'show', 'duration': 90},
      'delivery': {'code': 200, 'url': 'https://example.invalid/clip.m3u8', 'format': 'hls', 'country': 'BE'},
    }),
    Tf1TestVideo.unknown => _file('mediainfo_unknown'),
    Tf1TestVideo.rateLimited => http.Response('', 429, headers: {'retry-after': '30'}),
    _ => http.Response('{"media":{"error_code":"UNSUPPORTED"}}', 404, headers: _jsonHeaders),
  };

  http.Response _file(String name) =>
      http.Response(File('$_fixtures/$name.json').readAsStringSync(), 200, headers: _jsonHeaders);

  http.Response _body(Map<String, dynamic> body) => http.Response(jsonEncode(body), 200, headers: _jsonHeaders);
}
