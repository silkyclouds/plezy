import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/france24/france24_api.dart';
import 'package:plezy/replay/providers/france24/france24_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/france24';

const rootGuid = '78dcf358-9333-4fb2-a035-7b91e9705b13';
const videosGuid = 'ea148510-c824-4112-8e41-475cefb466d2';
const programmesGuid = '99cc9485-ede6-41ed-b671-399564be7859';
const latestGuid = '1f5a6e4d-370c-4ec3-9743-8dda577d07a1';
const editionsGuid = '81e5fb03-85ea-45db-8210-43adb6fe5206';

/// Programme that the recorded editions belong to.
const avecJudith = 'WBMZ533974-F24-FR-20250909';

/// Programme from the recorded latest-editions page, absent from the recorded programme list.
const lesCles = 'WBMZ540372-F24-FR-20250925';

/// Recorded newest edition of [avecJudith]; its video lists a 1080p file identical to `MP4` and a 720p file.
const avecJudithEdition = 'WBMZ705617-F24-FR-20261016';

/// Recorded clips of the video feed.
const clipWithAllFormats = 'DB3690B3-3650-4CAF-BDB3-C7E907DE36DF';
const clipWithTwoFormats = 'C31A21F6-9821-411A-BBE6-6A6CA28B1F08';

final testNow = DateTime.utc(2026, 10, 21, 9);

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Serves recorded France 24 responses, plus generated edition histories for programmes that need many pages.
class RecordedFrance24 {
  /// Edition histories by programme id, newest first, served 21 per page.
  final Map<String, List<Map<String, dynamic>>> histories = {};

  /// Replaces the recorded video feed when set.
  Map<String, dynamic>? videoFeed;

  /// Forces every catalogue request to answer with this status when set.
  int? status;
  Map<String, String> statusHeaders = const {};

  final List<Uri> requests = [];

  int get editionRequests => requests.where((u) => u.path.endsWith(editionsGuid)).length;

  List<Map<String, dynamic>> _listOf(Map<String, dynamic> page) =>
      ((page['result'] as Map<String, dynamic>)['list'] as List).cast<Map<String, dynamic>>();

  http.Response handle(http.Request request) {
    requests.add(request.url);
    if (request.url.queryParameters['token_application'] != France24Api.applicationToken) {
      return http.Response('{}', 401);
    }
    if (status != null) return http.Response('{}', status!, headers: statusHeaders);

    final guid = request.url.pathSegments.last;
    final query = request.url.queryParameters;
    final page = int.tryParse(query['page'] ?? '') ?? 1;
    final nid = query['nid'];
    final body = switch (guid) {
      rootGuid => fixture('root_fr'),
      programmesGuid => _programmes(page, nid),
      latestGuid => page == 1 ? fixture('latest_editions') : _empty(page, 24),
      videosGuid => _videos(page, nid),
      editionsGuid => _editions(page, nid),
      _ => null,
    };
    return body == null ? http.Response('{}', 404) : _json(body);
  }

  Map<String, dynamic> _programmes(int page, String? nid) {
    final first = fixture('programmes');
    if (nid != null) {
      final all = [..._listOf(first), ..._listOf(fixture('programmes_page2'))];
      return _page(all.where((p) => p['nid'] == nid).toList(), page: 1, perPage: 24);
    }
    return page == 1 ? first : (page == 2 ? fixture('programmes_page2') : _empty(page, 24));
  }

  Map<String, dynamic> _videos(int page, String? nid) {
    final feed = videoFeed ?? fixture('videos');
    if (nid != null) return _page(_listOf(feed).where((v) => v['nid'] == nid).toList(), page: 1, perPage: 25);
    return page == 1 ? feed : _empty(page, 25);
  }

  Map<String, dynamic> _editions(int page, String? nid) {
    final history = histories[nid];
    if (history != null) return _page(history, page: page, perPage: 21);
    if (nid == avecJudith) return page == 1 ? fixture('editions') : _empty(page, 21);
    return _empty(page, 21);
  }

  Map<String, dynamic> _empty(int page, int perPage) => _page(const [], page: page, perPage: perPage);

  Map<String, dynamic> _page(List<Map<String, dynamic>> items, {required int page, required int perPage}) {
    final from = (page - 1) * perPage;
    final slice = from >= items.length ? <Map<String, dynamic>>[] : items.skip(from).take(perPage).toList();
    return {
      'result': {
        'list': slice,
        'nb_total_item': items.length,
        'current_page': page,
        'last_page': items.isEmpty ? 1 : (items.length / perPage).ceil(),
        'nb_item_per_page': perPage,
      },
    };
  }

  http.Response _json(Map<String, dynamic> body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/vnd.fmm.json2-mobile+json; charset=utf-8'},
  );
}

/// A synthetic edition of [programme] on [day], cloned from the recorded one so every field has its real shape.
///
/// Set [withVideo] false for a text-only article and [created] to false for an edition that lacks a timestamp.
Map<String, dynamic> editionOn(
  String programme,
  DateTime day,
  int index, {
  bool withVideo = true,
  bool created = true,
  String? videoNid,
}) {
  final edition = jsonDecode(jsonEncode(fixture('editions')['result']['list'][0])) as Map<String, dynamic>;
  final stamp = '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';
  final video = (edition['main_video'] as List).first as Map<String, dynamic>;
  video['nid'] = videoNid ?? 'VIDEO$index-F24-FR-$stamp';
  edition['nid'] = 'EDITION$index-F24-FR-$stamp';
  edition['title'] = 'Edition $stamp';
  edition['created'] = created ? '${day.add(const Duration(hours: 6)).millisecondsSinceEpoch}' : '';
  edition['programs'] = {...(edition['programs'] as Map<String, dynamic>), 'nid': programme};
  edition['main_video'] = withVideo ? [video] : <Object>[];
  return edition;
}

/// A history of editions on [days], newest first, with consecutive indexes.
List<Map<String, dynamic>> historyOn(String programme, List<DateTime> days, {Set<int> withoutVideo = const {}}) => [
  for (var i = 0; i < days.length; i++) editionOn(programme, days[i], i, withVideo: !withoutVideo.contains(i)),
];

List<DateTime> everyNthDay(DateTime newest, int count, int step) => [
  for (var i = 0; i < count; i++) newest.subtract(Duration(days: i * step)),
];

France24Provider providerOver(RecordedFrance24 server, {DateTime? now}) {
  final client = MediaServerHttpClient(client: MockClient((r) async => server.handle(r)));
  final clock = (now == null) ? () => testNow : () => now;
  return France24Provider.withApi(
    France24Api(client, minGap: Duration.zero, clock: clock),
    clock: clock,
  );
}
