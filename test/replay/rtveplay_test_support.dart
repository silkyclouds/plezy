import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_api.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/rtveplay';
const _json = {'content-type': 'application/json; charset=utf-8'};

/// The moment the fake site considers "now": after every recorded publication date.
final rtveTestNow = DateTime.utc(2026, 10, 22, 12);

String rtveFixtureText(String name) => File('$_fixtures/$name').readAsStringSync();

Map<String, dynamic> rtveFixture(String name) => jsonDecode(rtveFixtureText('$name.json')) as Map<String, dynamic>;

/// A page envelope around [items], as every RTVE list answers.
Map<String, dynamic> rtvePage(List<Map<String, dynamic>> items, {int total = 0, int totalPages = 1}) => {
  'page': {
    'items': items,
    'number': 1,
    'size': items.length,
    'offset': 0,
    'total': total == 0 ? items.length : total,
    'totalPages': totalPages,
    'numElements': items.length,
  },
};

List<Map<String, dynamic>> rtveItemsOf(String fixture) =>
    ((rtveFixture(fixture)['page'] as Map)['items'] as List).cast<Map<String, dynamic>>();

/// A deep copy of a record that [edit] may change.
Map<String, dynamic> rtveEdited(Map<String, dynamic> record, void Function(Map<String, dynamic> copy) edit) {
  final copy = jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
  edit(copy);
  return copy;
}

ReplayRef rtveRef(String nativeId) => ReplayRef('rtveplay', nativeId);

const _hlsHost = 'rtvehlsvodlote7.rtve.es';

/// Serves recorded RTVE responses by host and path. Anything it does not know is a 404.
///
/// [overrides] replace a response for one path, matched as a suffix of the request path; [answer] is the default for
/// the three manifests of the recorded videos.
class RtveFakeSite {
  final List<http.Request> requests = [];
  final Map<String, http.Response Function(http.Request)> overrides = {};

  List<http.Request> to(String pathPart) => requests.where((r) => r.url.path.contains(pathPart)).toList();

  RtvePlayProvider provider() => RtvePlayProvider.withApi(api(), now: () => rtveTestNow);

  RtvePlayApi api() => RtvePlayApi(MediaServerHttpClient(client: MockClient((r) async => _handle(r))));

  http.Response _handle(http.Request request) {
    requests.add(request);
    for (final entry in overrides.entries) {
      if (request.url.path.endsWith(entry.key)) return entry.value(request);
    }
    final path = request.url.path;
    if (request.url.host == _hlsHost) return _manifest(path);
    if (path.startsWith('/ztnr/movil/thumbnail/rtveplayw/videos/')) return _streamList(path);
    if (request.url.host == 'api.rtve.es') return _search(request.url);
    return _catalogue(request.url);
  }

  http.Response _catalogue(Uri url) {
    final path = url.path;
    final page = url.queryParameters['page'] ?? '1';
    final json = switch (path) {
      '/api/videos.json' => page == '1' ? rtveFixture('videos_latest') : rtvePage(const [], total: 440414),
      '/api/programas.json' => rtveFixture('programas_page'),
      '/api/cadenas/748/programas.json' => rtveFixture('cadena_programas'),
      '/api/programas/175650.json' => rtveFixture('programa_detalle'),
      '/api/programas/175650/temporadas' => rtveFixture('temporadas'),
      '/api/programas/175650/temporadas/1000630/videos' => rtveFixture('temporada_videos'),
      '/api/programas/117610.json' => rtveFixture('programa_flat'),
      '/api/programas/117610/videos' => rtveFixture('programa_flat_videos'),
      '/api/programas/1573.json' => rtvePage([rtveItemsOf('search_programs').first]),
      '/api/programas/1573/videos' => rtveFixture('programa_videos_completos'),
      '/api/videos/16177116.json' => rtveFixture('video_item'),
      '/api/videos/16859989.json' => rtveFixture('video_item_geolocalizado'),
      '/api/videos/1888987.json' => rtveFixture('video_item_pasarela_403'),
      '/api/videos/16177116/subtitulos.json' => rtveFixture('subtitulos'),
      _ => null,
    };
    if (json == null) return http.Response('<html>not found</html>', 404, headers: {'content-type': 'text/html'});
    // Recorded lists are trimmed to their first page, so they must not promise more.
    (json['page'] as Map)['totalPages'] = 1;
    return http.Response(jsonEncode(json), 200, headers: _json);
  }

  http.Response _search(Uri url) {
    final empty = url.queryParameters['search'] == 'zzzz';
    final fixture = url.path.endsWith('/programs') ? 'search_programs' : 'search_contents';
    return http.Response(jsonEncode(empty ? rtvePage(const []) : rtveFixture(fixture)), 200, headers: _json);
  }

  http.Response _streamList(String path) {
    final id = path.split('/').last.replaceAll('.png', '');
    const known = {'16177116', '16859989', '1888987'};
    if (!known.contains(id)) return http.Response('', 404);
    return http.Response(rtveFixtureText('ztnr_$id.b64'), 200, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  /// Playable for the free video, refused for the two recorded blocked ones, with the headers RTVE sent.
  http.Response _manifest(String path) {
    if (path.contains('TE_SVVR876')) {
      return http.Response(
        rtveFixtureText('master.m3u8'),
        200,
        headers: {'content-type': 'application/vnd.apple.mpegurl'},
      );
    }
    if (path.contains('TE_SM6D14L3S')) return http.Response('', 403, headers: {'x-country': 'be'});
    if (path.contains('TE_SCUENT')) {
      return http.Response('', 403, headers: {'x-current-url': '/usuarios/pasarela/estado?idasset=1888987'});
    }
    return http.Response('', 404);
  }
}
