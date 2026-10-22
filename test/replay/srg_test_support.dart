import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// A recorded Integration Layer response, read from `test/replay/fixtures/<directory>/<name>.json`.
String srgFixture(String directory, String name) =>
    File('test/replay/fixtures/$directory/$name.json').readAsStringSync();

/// A recorded response decoded, so a test can adjust it before serving it.
Map<String, dynamic> srgFixtureMap(String directory, String name) =>
    jsonDecode(srgFixture(directory, name)) as Map<String, dynamic>;

http.Response srgJson(Object body, [int status = 200, Map<String, String> headers = const {}]) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

/// What the server answers for a list it has nothing in.
const srgEmptyLists = '{"mediaList":[],"showList":[],"searchResultMediaList":[],"searchResultShowList":[]}';

/// A client whose requests are answered by [route]; every request is appended to [log].
MediaServerHttpClient srgClient(http.Response Function(http.Request) route, {List<http.Request>? log}) {
  return MediaServerHttpClient(
    client: MockClient((request) async {
      log?.add(request);
      return route(request);
    }),
  );
}

/// The path of a request below the Integration Layer root, such as `srf/showList/tv/alphabetical`.
String srgPath(http.Request request) => request.url.path.replaceFirst('/integrationlayer/2.0/', '');

/// A video as the lists describe it, with only the fields the providers read.
Map<String, dynamic> srgVideo(
  String unit,
  String id,
  String date, {
  String show = 'daily',
  int count = 450,
  String type = 'EPISODE',
  bool playableAbroad = true,
}) => {
  'id': id,
  'urn': 'urn:$unit:video:$id',
  'mediaType': 'VIDEO',
  'type': type,
  'title': 'Sendung $id',
  'date': date,
  'duration': 600000,
  'validTo': '2099-12-31T23:59:59+01:00',
  'playableAbroad': playableAbroad,
  'show': {'id': show, 'title': 'Journal', 'numberOfEpisodes': count},
};

/// One page of a daily programme with [total] episodes, one per day counting back from 2026-10-20, 100 per page.
http.Response srgDailyPage(String unit, int index, int total) {
  final start = DateTime.utc(2026, 10, 20);
  final items = [
    for (var n = index * 100; n < total && n < index * 100 + 100; n++)
      srgVideo(
        unit,
        'd$n',
        '${start.subtract(Duration(days: n)).toIso8601String().substring(0, 10)}T19:30:00+02:00',
        count: total,
      ),
  ];
  final next = (index + 1) * 100 < total
      ? 'https://il.srgssr.ch/integrationlayer/2.0/$unit/mediaList/video/latest/byShow/daily?pageSize=100&next=${index + 1}'
      : null;
  return srgJson({'next': ?next, 'mediaList': items});
}

/// A media composition with one chapter, as the playback call returns it.
Map<String, dynamic> srgComposition(
  String unit, {
  String? blockReason,
  bool? playableAbroad,
  List<Map<String, dynamic>>? resources,
}) => {
  'chapterList': [
    {
      'id': 'x1',
      'urn': 'urn:$unit:video:x1',
      'mediaType': 'VIDEO',
      'type': 'EPISODE',
      'title': 'Ein Film',
      'blockReason': ?blockReason,
      'playableAbroad': ?playableAbroad,
      'resourceList': ?resources,
    },
  ],
};

Map<String, dynamic> srgResource(String streaming, String url, {List<Map<String, String>>? drm}) => {
  'url': url,
  'streaming': streaming,
  'drmList': ?drm,
};
