import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/france24/france24_api.dart';
import 'package:plezy/replay/providers/france24/france24_language.dart';
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

/// English tree: programme with three recorded editions, one with UUID edition ids, and the YouTube-only one.
const factOrFake = 'WB5973796-F24-EN-20190225';
const business = 'WB5442702-F24-EN-20130826';
const observers = 'WB5103037-F24-EN-20101011';

final testNow = DateTime.utc(2026, 10, 21, 9);

/// The recorded responses of one language tree and the addresses that serve them.
class RecordedTree {
  final France24Language language;
  final String root;
  final String videosId;
  final String programmesId;
  final String latestId;

  /// Fixture names of the programme list pages, first page first.
  final List<String> programmePages;
  final String latestEditions;
  final String videos;

  /// Fixture name of the first page of editions, by programme id.
  final Map<String, String> editions;

  const RecordedTree({
    required this.language,
    required this.root,
    required this.videosId,
    required this.programmesId,
    required this.latestId,
    required this.programmePages,
    required this.latestEditions,
    required this.videos,
    required this.editions,
  });

  static const french = RecordedTree(
    language: France24Language.french,
    root: 'root_fr',
    videosId: videosGuid,
    programmesId: programmesGuid,
    latestId: latestGuid,
    programmePages: ['programmes', 'programmes_page2'],
    latestEditions: 'latest_editions',
    videos: 'videos',
    editions: {avecJudith: 'editions'},
  );

  static const english = RecordedTree(
    language: France24Language.english,
    root: 'english/root',
    videosId: 'a25eccc6-224a-49dc-bd4a-237b090d93be',
    programmesId: '1eca84d5-5fd6-4061-9c7c-d95ee193c7c7',
    latestId: 'd6af02a5-7b7e-439f-bab5-ccecab16f9fa',
    programmePages: ['english/programmes', 'english/programmes_page2'],
    latestEditions: 'english/latest_editions',
    videos: 'english/videos',
    editions: {
      factOrFake: 'english/editions',
      business: 'english/editions_business',
      observers: 'english/editions_observers',
    },
  );
}

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Serves recorded France 24 responses, plus generated edition histories for programmes that need many pages.
class RecordedFrance24 {
  final RecordedTree tree;

  RecordedFrance24({this.tree = RecordedTree.french});

  /// Edition histories by programme id, newest first, served 21 per page.
  final Map<String, List<Map<String, dynamic>>> histories = {};

  /// Replaces the recorded video feed when set.
  Map<String, dynamic>? videoFeed;

  /// Replaces the recorded programme list when set, served 24 per page.
  List<Map<String, dynamic>>? programmeList;

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
      rootGuid => fixture(tree.root),
      _ when guid == tree.programmesId => _programmes(page, nid),
      _ when guid == tree.latestId => page == 1 ? fixture(tree.latestEditions) : _empty(page, 24),
      _ when guid == tree.videosId => _videos(page, nid),
      editionsGuid => _editions(page, nid),
      _ => null,
    };
    return body == null ? http.Response('{}', 404) : _json(body);
  }

  Map<String, dynamic> _programmes(int page, String? nid) {
    final replaced = programmeList;
    if (replaced != null) {
      final matching = nid == null ? replaced : replaced.where((p) => p['nid'] == nid).toList();
      return _page(matching, page: nid == null ? page : 1, perPage: 24);
    }
    final pages = [for (final name in tree.programmePages) fixture(name)];
    if (nid != null) {
      final all = [for (final p in pages) ..._listOf(p)];
      return _page(all.where((p) => p['nid'] == nid).toList(), page: 1, perPage: 24);
    }
    return page <= pages.length ? pages[page - 1] : _empty(page, 24);
  }

  Map<String, dynamic> _videos(int page, String? nid) {
    final feed = videoFeed ?? fixture(tree.videos);
    if (nid != null) return _page(_listOf(feed).where((v) => v['nid'] == nid).toList(), page: 1, perPage: 25);
    return page == 1 ? feed : _empty(page, 25);
  }

  Map<String, dynamic> _editions(int page, String? nid) {
    final history = histories[nid];
    if (history != null) return _page(history, page: page, perPage: 21);
    final recorded = tree.editions[nid];
    if (recorded != null) return page == 1 ? fixture(recorded) : _empty(page, 21);
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
  String base = 'editions',
}) {
  final edition = jsonDecode(jsonEncode(fixture(base)['result']['list'][0])) as Map<String, dynamic>;
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
    France24Api(client, language: server.tree.language, minGap: Duration.zero, clock: clock),
    clock: clock,
  );
}
