import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_api.dart';
import 'package:plezy/replay/providers/zdfmediathek/zdfmediathek_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const zdfFixtureDir = 'test/replay/fixtures/zdfmediathek';

/// The moment every test runs at, so recorded availability windows keep their meaning.
final zdfNow = DateTime.utc(2026, 10, 22, 12);

String zdfFixtureText(String name) => File('$zdfFixtureDir/$name.json').readAsStringSync();

Map<String, dynamic> zdfFixture(String name) => jsonDecode(zdfFixtureText(name)) as Map<String, dynamic>;

const _documentFixtures = {
  'die-bergretter-104': 'brand_with_seasons',
  'heute-journal-104': 'brand_news_heute_journal',
  'serien-100': 'category_serien',
  'verzeihen-102': 'video_document_clear',
  'nordkoreas-geheimnisse-100': 'video_document_geo_dach',
  'jagd-auf-virus-x-droht-die-naechste-pandemie-100': 'video_document_geo_de',
  'freies-land-116': 'video_document_fsk_gated',
};

/// A stand-in for ZDF: recorded responses by URL, edited documents on top, and a CDN that refuses restricted videos.
class ZdfFakeSite {
  static const _apiHost = 'zdf-prod-futura.zdf.de';

  /// Document bodies that replace or add to the recorded ones, by document id.
  final Map<String, Map<String, dynamic>> documents = {};
  final List<Uri> requests = [];
  final List<String> userAgents = [];

  /// Whether the CDN serves videos flagged for Germany, Austria and Switzerland, as it does inside those countries.
  bool insideDach = false;

  int get streamRequests => requests.where((u) => u.host != _apiHost).length;

  int requestsTo(String pathPart) => requests.where((u) => u.host == _apiHost && u.path.contains(pathPart)).length;

  ZdfMediathekProvider provider() => ZdfMediathekProvider.withApi(api(), clock: () => zdfNow);

  ZdfApi api() => ZdfApi(
    MediaServerHttpClient(client: MockClient(_handle)),
    gap: Duration.zero,
    clock: () => zdfNow,
  );

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    requests.add(url);
    userAgents.add(request.headers['User-Agent'] ?? request.headers['user-agent'] ?? '');
    if (url.host != _apiHost) return _stream(url);
    final path = url.path.replaceFirst('/mediathekV2/', '');
    if (path == 'start-page') return _json(zdfFixtureText('start_page'));
    if (path == 'categories-overview') return _json(zdfFixtureText('categories_overview'));
    if (path == 'document/sendungen-100') return _json(zdfFixtureText('brands_a_z'));
    if (path == 'search') return _search(url);
    if (path.startsWith('document/')) return _document(Uri.decodeComponent(path.substring('document/'.length)));
    return http.Response('{}', 404);
  }

  http.Response _search(Uri url) {
    final first = (url.queryParameters['page'] ?? '1') == '1';
    if (url.queryParameters['q'] == 'tagesschau' && first) return _json(zdfFixtureText('search'));
    return _json('{"results":[],"nextPage":false,"totalResultsCount":0}');
  }

  http.Response _document(String id) {
    if (id == 'busy-100') return http.Response('slow down', 429, headers: {'retry-after': '30'});
    final edited = documents[id];
    if (edited != null) return _json(jsonEncode(edited));
    final file = _documentFixtures[id];
    return file == null ? http.Response('{}', 404) : _json(zdfFixtureText(file));
  }

  http.Response _stream(Uri url) {
    final restricted = url.path.contains('/dach/') || url.path.contains('/de/');
    if (restricted && !insideDach) return http.Response('Access Denied', 403);
    return http.Response('#EXTM3U', 206);
  }

  http.Response _json(String body) =>
      http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});
}

/// A recorded video document with [edit] applied to its `document` object.
Map<String, dynamic> zdfEditedDocument(String fixture, void Function(Map<String, dynamic> document) edit) {
  final page = zdfFixture(fixture);
  edit(page['document'] as Map<String, dynamic>);
  return page;
}

/// A video teaser as a show row lists it.
Map<String, dynamic> zdfEpisodeTeaser(
  String id,
  String title, {
  String? brandId,
  String? season,
  String? episode,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'type': 'video',
  'titel': title,
  'contentType': 'episode',
  'currentVideoType': 'episode',
  'hasVideo': true,
  'geoLocation': 'none',
  'fsk': 'none',
  'length': 1500,
  'brandId': ?brandId,
  'seasonNumber': ?season,
  'episodeNumber': ?episode,
  ...extra,
};

/// A brand document whose rows hold [clusters], each a name and its teasers.
Map<String, dynamic> zdfBrandPage(String id, String title, Map<String, List<Map<String, dynamic>>> clusters) => {
  'document': {'id': id, 'type': 'brand', 'titel': title, 'hasVideo': true, 'structureNodePath': '/zdf/serien/$id'},
  'cluster': [
    for (final entry in clusters.entries) {'name': entry.key, 'type': 'teaser', 'teaser': entry.value},
  ],
};
