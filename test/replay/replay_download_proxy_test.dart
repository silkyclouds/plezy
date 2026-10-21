import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/download/replay_download_proxy.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('replay_proxy'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A stand-in for ffmpeg: prints [body] and exits with [code].
  String fakeFfmpeg(String body, {int code = 0}) {
    final script = File('${dir.path}/ffmpeg')..writeAsStringSync("#!/bin/sh\nprintf '$body'\nexit $code\n");
    Process.runSync('chmod', ['755', script.path]);
    return script.path;
  }

  Future<List<int>> fetch(Uri url) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      return await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    } finally {
      client.close(force: true);
    }
  }

  test('a registered stream is served as the converter output', () async {
    final proxy = ReplayDownloadProxy(ffmpegPath: fakeFfmpeg('MP4-BYTES'));
    addTearDown(proxy.close);
    final url = await proxy.serve(Uri.parse('https://example.test/master.m3u8'));
    expect(url!.path, endsWith('.mp4'));
    expect(utf8.decode(await fetch(url)), 'MP4-BYTES');
  });

  test('a conversion that fails is reported as a broken transfer, not a short file', () async {
    final proxy = ReplayDownloadProxy(ffmpegPath: fakeFfmpeg('PART', code: 1));
    addTearDown(proxy.close);
    final url = await proxy.serve(Uri.parse('https://example.test/master.m3u8'));
    await expectLater(fetch(url!), throwsA(isA<Exception>()));
  });

  test('an unknown path is not found', () async {
    final proxy = ReplayDownloadProxy(ffmpegPath: fakeFfmpeg('X'));
    addTearDown(proxy.close);
    final url = await proxy.serve(Uri.parse('https://example.test/a.m3u8'));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(url!.replace(path: '/dl/999.mp4'))).close();
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('without ffmpeg nothing is served', () async {
    final proxy = ReplayDownloadProxy.unavailable();
    expect(proxy.isAvailable, isFalse);
    expect(await proxy.serve(Uri.parse('https://example.test/a.m3u8')), isNull);
  });
}
