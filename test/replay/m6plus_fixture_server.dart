import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_api.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/m6plus';
const _servicePath = '/services/6play/';

/// Id of a copy of Pretty Little Liars whose season and episode fields are removed, newest episode first.
const titlesOnlyProgram = '99001';

/// Date the provider believes it is, so publication windows are deterministic.
final fixtureNow = DateTime.utc(2026, 10, 21, 12);

dynamic readFixture(String name) => jsonDecode(File('$_fixtures/$name.json').readAsStringSync());

/// Serves recorded M6+ responses by URL and records what was asked.
class M6plusFixtureServer {
  /// When true, every manifest request is refused the way a foreign country is.
  bool manifestBlocked = false;
  int manifestStatus = 200;
  bool fullFirstPage = false;
  final List<Uri> requests = [];
  final Map<String, Map<String, dynamic>> extraVideos = {};
  final Map<String, dynamic> extraPrograms = {};
  late final Map<String, Map<String, dynamic>> _videosById = _indexVideos();

  M6plusProvider provider() {
    final http = MediaServerHttpClient(client: MockClient((r) async => handle(r)));
    return M6plusProvider.withApi(M6plusApi(http, minInterval: Duration.zero), clock: () => fixtureNow);
  }

  M6plusApi api({Duration minInterval = Duration.zero}) =>
      M6plusApi(MediaServerHttpClient(client: MockClient((r) async => handle(r))), minInterval: minInterval);

  http.Response handle(http.Request request) {
    requests.add(request.url);
    if (request.url.host == 'lbcdn.6cloud.fr') return _manifest();
    final tail = request.url.path.split(_servicePath).last;
    final segments = tail.split('/');
    final query = request.url.queryParameters;
    if (segments.first == 'programs') return _programs(segments, query);
    if (segments.first == 'folders') return _json(segments[1] == '8' ? readFixture('folder_programs') : []);
    if (segments.first == 'videos') return _video(segments[1]);
    return http.Response('{}', 404);
  }

  http.Response _programs(List<String> segments, Map<String, String> query) {
    if (segments.length == 1) {
      if (query['offset'] != '0') return _json([]);
      final page = readFixture('programs_page') as List;
      if (!fullFirstPage) return _json([...page, ...extraPrograms.values]);
      return _json([for (var i = 0; i < 100; i++) page[i % page.length]]);
    }
    final id = segments[1];
    if (segments.length == 2) {
      final program = extraPrograms[id] ?? _programFile(id);
      return program == null ? _notFound() : _json(program);
    }
    return _json(_videos(id, query['type'] ?? 'vi', query['offset'] ?? '0'));
  }

  dynamic _programFile(String id) {
    if (id == titlesOnlyProgram) return {...readFixture('program_28545') as Map, 'id': 99001, 'title': 'Titles only'};
    final file = File('$_fixtures/program_$id.json');
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) : null;
  }

  List<dynamic> _videos(String id, String type, String offset) {
    if (offset != '0') return [];
    if (id == titlesOnlyProgram) return _titlesOnly();
    final file = File('$_fixtures/videos_${id}_$type.json');
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) as List : [];
  }

  /// Season and episode numbers removed from the metadata, as when only the title says them.
  List<dynamic> _titlesOnly() {
    final videos = (readFixture('videos_28545_vi') as List).reversed.map((v) {
      final copy = jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
      (copy['program'] as Map)['id'] = 99001;
      final product = ((copy['clips'] as List).first as Map)['product'] as Map;
      product
        ..['season'] = null
        ..['episode'] = null
        ..['season_title'] = null;
      return copy;
    });
    return videos.toList();
  }

  http.Response _video(String id) {
    if (id == 'clip_429') return http.Response('slow down', 429, headers: {'retry-after': '30'});
    final video = extraVideos[id] ?? _videosById[id];
    return video == null ? _notFound() : _json(video);
  }

  http.Response _manifest() {
    if (manifestBlocked) {
      const body =
          'Your country : BE is not allowed to access this resource. '
          'Allowed countries : AD, FR, GP, GF, MQ, YT, MC, NC, PF, RE, BL, MF, PM, TF, WF ip detected: 192.0.2.1';
      return http.Response(body, 403, headers: {'content-type': 'text/html; charset=UTF-8'});
    }
    return http.Response('#EXTM3U\n', manifestStatus, headers: {'content-type': 'application/vnd.apple.mpegurl'});
  }

  Map<String, Map<String, dynamic>> _indexVideos() {
    final index = <String, Map<String, dynamic>>{};
    for (final file in Directory(_fixtures).listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.startsWith('video')) continue;
      final body = jsonDecode(file.readAsStringSync());
      for (final video in body is List ? body : [body]) {
        index[(video as Map<String, dynamic>)['id'] as String] = video;
      }
    }
    return index;
  }

  http.Response _json(Object? body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  http.Response _notFound() =>
      http.Response('{"error":{"code":404,"message":"not found"}}', 404, headers: {'content-type': 'application/json'});

  /// A copy of a recorded clip whose streams only accept [countries].
  Map<String, dynamic> restrictedCopy(String id, List<String> countries) {
    final copy = jsonDecode(jsonEncode(_videosById[id])) as Map<String, dynamic>;
    final encoded = base64.encode(utf8.encode(countries.join('|')));
    for (final asset in (((copy['clips'] as List).first as Map)['assets'] as List).cast<Map<String, dynamic>>()) {
      final url = Uri.parse(asset['full_physical_path'] as String);
      asset['full_physical_path'] = url
          .replace(queryParameters: {...url.queryParameters, 'countries': encoded})
          .toString();
    }
    return copy;
  }
}
