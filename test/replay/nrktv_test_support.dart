import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_api.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/nrktv';

/// The moment every test runs at: the recorded fixtures were taken that day, and tonight's news is not yet out.
final nrkNow = DateTime.utc(2026, 10, 22, 12);

ReplayRef nrkTestRef(String nativeId) => ReplayRef('nrktv', nativeId);

String nrkFixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

Map<String, dynamic> nrkJson(String name) => jsonDecode(nrkFixture(name)) as Map<String, dynamic>;

/// A recorded response with [edit] applied, for outcomes that cannot be recorded on demand.
String nrkEdited(String name, void Function(Map<String, dynamic> json) edit) {
  final json = nrkJson(name);
  edit(json);
  return jsonEncode(json);
}

const _json = {'content-type': 'application/json'};

http.Response nrkReply(String body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response(body, status, headers: {..._json, ...headers});

const _byPath = <String, String>{
  '/tv/pages': 'pages_list',
  '/tv/pages/frontpage': 'frontpage',
  '/tv/pages/dokumentar': 'page_dokumentar',
  '/tv/catalog/series/humoretaten': 'series_sequential',
  '/tv/catalog/series/humoretaten/seasons/4': 'season_sequential_4',
  '/tv/catalog/series/hestesport': 'series_standard',
  '/tv/catalog/series/hestesport/seasons/2022': 'season_standard_2022',
  '/tv/catalog/series/dagsrevyen': 'series_news',
  '/tv/catalog/series/dagsrevyen/seasons/202610': 'season_news_202610',
  '/tv/catalog/programs/OFAA21000105': 'program_world',
  '/tv/catalog/programs/KMNO10057925': 'program_geoblocked',
  '/tv/catalog/programs/NNFA19102126': 'program_news',
  '/tv/catalog/programs/MSUI42006021': 'program_episode',
  '/playback/metadata/program/OFAA21000105': 'metadata_standalone',
  '/playback/metadata/program/NNFA19102126': 'metadata_news',
  '/playback/metadata/program/MSUI42006021': 'metadata_episode',
  '/playback/manifest/program/IUFH21002726': 'manifest_playable',
  '/playback/manifest/program/KMNO10057925': 'manifest_geoblocked',
  '/playback/manifest/program/NNFA19102226': 'manifest_upcoming',
  '/playback/manifest/program/CHANNEL': 'manifest_channel_geoblocked',
  '/medium/tv/letters': 'index_letters',
  '/medium/tv/letters/a/indexelements': 'index_letter_a',
  '/medium/tv/letters/b/indexelements': 'index_letter_b',
};

/// Serves the recorded responses by path. Anything else is NRK's own 404, and `RATELIMITED` is a 429.
http.Response nrkRoute(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/RATELIMITED')) return nrkReply('{}', status: 429, headers: {'retry-after': '30'});
  if (path == '/search') {
    final empty = request.url.queryParameters['q'] == 'zzzz';
    return nrkReply(empty ? '{"hits":[]}' : nrkFixture('search'));
  }
  final name = _byPath[path];
  if (name == null) return nrkReply('{"message":"The requested resource could not be found"}', status: 404);
  return nrkReply(nrkFixture(name));
}

/// The API over recorded responses. [log] collects every request; [overrides] replace a path's answer.
NrkApi nrkApi({List<http.Request>? log, Map<String, String> overrides = const {}}) {
  final client = MockClient((request) async {
    log?.add(request);
    final override = overrides[request.url.path];
    return override != null ? nrkReply(override) : nrkRoute(request);
  });
  return NrkApi(MediaServerHttpClient(client: client), now: () => nrkNow);
}

NrkTvProvider nrkProvider({List<http.Request>? log, Map<String, String> overrides = const {}}) => NrkTvProvider.withApi(
  nrkApi(log: log, overrides: overrides),
  now: () => nrkNow,
);
