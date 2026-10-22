import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real Al Jazeera English site.
/// Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/aljazeera_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';
  const patience = Timeout(Duration(minutes: 5));

  test(
    'a programme opens down to a playable HLS stream',
    () async {
      final http = MediaServerHttpClient();
      final provider = AljazeeraProvider(http);
      final rails = await provider.home();
      expect(rails, isNotEmpty);
      // ignore: avoid_print
      print('home rails: ${rails.map((r) => '${r.id}=${r.titles.length}').join(' ')}');

      final hits = await provider.search('inside story');
      final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Inside Story');
      final seasons = await provider.children(show.ref);
      expect(seasons, isNotEmpty);
      // ignore: avoid_print
      print('inside story seasons: ${seasons.map((s) => s.title).join(' ')}');

      final episodes = await provider.children(seasons.last.ref);
      expect(episodes, isNotEmpty);
      expect(episodes.first.episodeNumber, 1);
      // ignore: avoid_print
      print('newest season: ${episodes.length} episodes, last "${episodes.last.title}"');

      final playback = await provider.playback(episodes.last.ref);
      expect(playback.isPlayable, isTrue, reason: playback.message);
      final master = await http.get(playback.streams.first.url.toString());
      expect(master.statusCode, 200);
      expect(master.data.toString(), startsWith('#EXTM3U'));
      expect(master.data.toString(), contains('SUBTITLES'));

      final picture = provider.imageUrl(episodes.last.backdropUrl!, width: 640);
      expect((await http.get(picture)).statusCode, 200);
    },
    skip: live ? false : skip,
    timeout: patience,
  );

  test(
    'programmes list only episodes that play',
    () async {
      final provider = AljazeeraProvider(MediaServerHttpClient());
      var asked = 0;
      var played = 0;
      for (final slug in ['witness', '101-east', 'fault-lines', 'al-jazeera-world', 'the-listening-post']) {
        final show = await provider.title(ReplayRef('aljazeera', slug));
        if (show == null) continue;
        final seasons = await provider.children(show.ref);
        final episodes = seasons.isEmpty ? <ReplayTitle>[] : await provider.children(seasons.last.ref);
        var ok = 0;
        for (final episode in episodes.reversed.take(3)) {
          asked++;
          final playback = await provider.playback(episode.ref);
          if (playback.isPlayable) {
            ok++;
            played++;
          }
        }
        // ignore: avoid_print
        print('$slug: ${seasons.length} seasons, ${episodes.length} listed in the newest, $ok of 3 newest play');
      }
      expect(asked, greaterThan(0));
      expect(played, asked, reason: 'a listed episode must play');
    },
    skip: live ? false : skip,
    timeout: patience,
  );
}
