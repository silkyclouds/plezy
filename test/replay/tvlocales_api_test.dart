import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_api.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'tvlocales_fixtures.dart';

final _page = Uri.parse('https://www.telemb.be/emissions');

TvLocalesApi _api(Future<http.Response> Function(http.Request) handler, {Duration minGap = Duration.zero}) =>
    TvLocalesApi(MediaServerHttpClient(client: MockClient(handler)), minGap: minGap);

void main() {
  test('a page is fetched once for concurrent and repeated calls', () async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return htmlResponse('<html>ok</html>');
    });
    await Future.wait([api.page(_page), api.page(_page)]);
    await api.page(_page);
    expect(calls, 1);
  });

  test('a failed page is fetched again on the next call', () async {
    var calls = 0;
    final api = _api((_) async => ++calls == 1 ? http.Response('boom', 500) : htmlResponse('<html>ok</html>'));
    await expectLater(api.page(_page), throwsA(isA<MediaServerHttpException>()));
    expect(await api.page(_page), contains('ok'));
  });

  test('an expired cache entry is fetched again', () async {
    var calls = 0;
    final api = TvLocalesApi(
      MediaServerHttpClient(
        client: MockClient((_) async {
          calls++;
          return htmlResponse('<html>ok</html>');
        }),
      ),
      minGap: Duration.zero,
      pageTtl: Duration.zero,
    );
    await api.page(_page);
    await api.page(_page);
    expect(calls, 2);
  });

  test('429 and 503 raise a rate limit with the delay the site asked for', () async {
    for (final status in [429, 503]) {
      final api = _api((_) async => http.Response('', status, headers: {'retry-after': '45'}));
      await expectLater(
        api.page(_page),
        throwsA(
          isA<TvLocalesRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 45)),
        ),
      );
    }
  });

  test('a missing Retry-After falls back to a minute', () async {
    final api = _api((_) async => http.Response('', 429));
    await expectLater(
      api.page(_page),
      throwsA(isA<TvLocalesRateLimitedException>().having((e) => e.retryAfter.inSeconds, 'seconds', 60)),
    );
  });

  test('requests to the sites are spaced by the minimum gap', () async {
    final api = _api((_) async => htmlResponse('<html>ok</html>'), minGap: const Duration(milliseconds: 60));
    final clock = Stopwatch()..start();
    for (final path in ['/a', '/b', '/c']) {
      await api.page(_page.replace(path: path));
    }
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(100));
  });

  test('player configurations are never cached', () async {
    var calls = 0;
    final api = _api((_) async {
      calls++;
      return jsonResponse('{"video":{}}');
    });
    const id = 'a30728c1-5ff5-4435-a10b-0f0454743de2';
    await api.embed(id);
    await api.embed(id);
    expect(calls, 2);
  });

  test('a player configuration that is not an object is refused', () async {
    final api = _api((_) async => jsonResponse('[1, 2]'));
    await expectLater(api.embed('a30728c1-5ff5-4435-a10b-0f0454743de2'), throwsA(isA<MediaServerHttpException>()));
  });
}
