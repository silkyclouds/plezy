import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_api.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/orftvthek';
const _apiPrefix = '/api/v4.3/';

/// The moment every test runs at: 09:00 in Vienna on the day the fixtures were recorded.
final orfNow = DateTime.utc(2026, 10, 22, 7);

const orfTestUser = 'test-user';
const orfTestPassword = 'not-a-real-password';

ReplayRef orfTestRef(String nativeId) => ReplayRef('orftvthek', nativeId);

String orfFixture(String name) => File('$_fixtures/$name').readAsStringSync();

Map<String, dynamic> orfJson(String name) => jsonDecode(orfFixture('$name.json')) as Map<String, dynamic>;

/// A recorded response with [edit] applied, for outcomes that cannot be recorded on demand.
String orfEdited(String name, void Function(Map<String, dynamic> json) edit) {
  final json = orfJson(name);
  edit(json);
  return jsonEncode(json);
}

String orfBasic(String user, String password) => 'Basic ${base64Encode(utf8.encode('$user:$password'))}';

class _Reply extends http.StreamedResponse implements http.BaseResponseWithUrl {
  _Reply(super.stream, super.statusCode, {required this.url, super.headers, super.request});

  @override
  final Uri url;
}

const _apiRoutes = <String, String>{
  'page/start': 'page_start',
  'page/startpage/highlights': 'startpage_highlights',
  'lane/13870317': 'lane',
  'lane/mostviewed': 'lane_mostviewed',
  'genres': 'genres',
  'genre/1178/episodes': 'episodes_page',
  'genre/1178/profiles': 'genre_profiles',
  'episodes': 'episodes_page',
  'profiles': 'profiles_index',
  'profile/1203': 'profile',
  'profile/1203/episodes': 'profile_episodes',
  'profile/13898827/episodes': 'profile_kiwi2_episodes',
  'profile/13899279/episodes': 'profile_soko5_episodes',
  'profile/13844820/episodes': 'profile_dok1_episodes',
  'episode/14343509': 'episode_worldwide',
  'episode/14343582': 'episode_austria_only',
  'episode/14343468': 'episode_drm',
  'segment/16174066': 'segment_worldwide',
  'segment/16173844': 'segment_austria_only',
  'subtitle/1347705': 'subtitle',
  'subtitle/1350408': 'subtitle',
};

/// ORF ON as recorded: the web app's page, the JSON API behind Basic auth and the stream host.
///
/// Anything the recordings do not cover is ORF's own 404. [overrides] replace the answer for an API path, and
/// [rotatePassword] plays the part of a new web build that changes the pair.
class OrfFakeSite extends http.BaseClient {
  OrfFakeSite({this.insideAustria = false, Map<String, String>? overrides}) : overrides = overrides ?? {};

  /// Whether the viewer is in Austria, which decides where an Austria-only stream address ends.
  final bool insideAustria;
  final Map<String, String> overrides;
  final List<http.BaseRequest> log = [];
  int pageReads = 0;
  String _pagePassword = orfTestPassword;
  String _acceptedPassword = orfTestPassword;
  String? pageWithoutSettings;

  void rotatePassword(String next) {
    _pagePassword = next;
    _acceptedPassword = next;
  }

  /// The API paths asked for, without the version prefix.
  List<String> get apiPaths => [
    for (final r in log)
      if (r.url.host == 'api-tvthek.orf.at' && r.url.path.startsWith(_apiPrefix))
        r.url.path.substring(_apiPrefix.length),
  ];

  Iterable<http.BaseRequest> requestsTo(String host) => log.where((r) => r.url.host == host);

  MediaServerHttpClient get client => MediaServerHttpClient(client: this);

  OrfTvthekProvider get provider => OrfTvthekProvider.withApi(OrfApi(client, now: () => orfNow), now: () => orfNow);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    log.add(request);
    final url = request.url;
    return switch (url.host) {
      'on.orf.at' => _page(request),
      'api-tvthek.orf.at' => _api(request),
      'apasfiis.sf.apa.at' => _stream(request),
      _ => _reply(request, '{}', status: 404),
    };
  }

  http.StreamedResponse _page(http.BaseRequest request) {
    pageReads++;
    final body = pageWithoutSettings ?? orfFixture('web_page.html').replaceFirst(orfTestPassword, _pagePassword);
    return _reply(request, body, type: 'text/html; charset=utf-8');
  }

  http.StreamedResponse _api(http.BaseRequest request) {
    if (request.headers['Authorization'] != orfBasic(orfTestUser, _acceptedPassword)) {
      return _reply(request, 'Unauthorized', status: 401, type: 'text/html');
    }
    final path = request.url.path.substring(_apiPrefix.length);
    if (path == 'episode/429') return _reply(request, '{}', status: 429, extra: {'retry-after': '30'});
    final override = overrides[path];
    if (override != null) return _reply(request, override);
    if (path.startsWith('search/')) return _reply(request, _search(path));
    final name = _apiRoutes[path];
    if (name == null) return _reply(request, '{"error":"not found"}', status: 404);
    return _reply(request, orfFixture('$name.json'));
  }

  String _search(String path) {
    if (path == 'search/zzzz') {
      const empty = {'items': [], 'total': 0, 'page_count': 0, 'next': null};
      return jsonEncode({
        'search': {'episodes': empty, 'segments': empty, 'history': empty},
      });
    }
    return orfFixture('search.json');
  }

  /// Austria-only recordings end at the geo-protection slate unless the viewer is in Austria.
  http.StreamedResponse _stream(http.BaseRequest request) {
    final path = request.url.path;
    if (path.contains('broken')) return _reply(request, 'unavailable', status: 503, type: 'text/plain');
    final slate = path.contains('cms-austria') && !insideAustria;
    final end = slate
        ? Uri.parse(
            'https://apasfiis.sf.apa.at/gp_nas/_definst_/nas/gp/online/insert_geoprotection_hr.smil/manifest.m3u8',
          )
        : Uri.parse('https://vod-ww.mdn.ors.at/cms/online/programme.smil/playlist.m3u8');
    return _reply(request, orfFixture('slate_master.m3u8'), type: 'application/vnd.apple.mpegurl', url: end);
  }

  http.StreamedResponse _reply(
    http.BaseRequest request,
    String body, {
    int status = 200,
    String type = 'application/json',
    Map<String, String> extra = const {},
    Uri? url,
  }) => _Reply(
    Stream.value(utf8.encode(body)),
    status,
    url: url ?? request.url,
    headers: {'content-type': type, ...extra},
    request: request,
  );
}

/// The titles of every rail, in order.
List<ReplayTitle> orfAllTitles(Iterable<ReplayRail> rails) => [for (final rail in rails) ...rail.titles];
