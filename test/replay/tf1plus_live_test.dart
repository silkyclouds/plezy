import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real TF1+ gateways. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/tf1plus_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  final skip = live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network';

  late Tf1PlusProvider provider;
  setUp(() => provider = Tf1PlusProvider(MediaServerHttpClient()));

  test('the menu, the landing page and a full listing page are served', () async {
    expect(await provider.categories(), isNotEmpty);
    final rails = await provider.home();
    expect(rails, isNotEmpty);
    final page = await provider.listing('series');
    expect(page.titles, hasLength(20));
    expect(page.totalCount, greaterThan(100));
    final next = await provider.listing('series', page: 1);
    expect(next.titles.first.ref, isNot(page.titles.first.ref));
    final everything = await provider.listing(replayAllBrowseId);
    expect(everything.totalCount, greaterThan(1000));
  }, skip: skip);

  test('a series goes down to numbered episodes, and none of them plays', () async {
    final hits = await provider.search('hpi');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'HPI');
    final seasons = await provider.children(show.ref);
    expect(seasons.map((s) => s.seasonNumber), orderedEquals(List.generate(seasons.length, (i) => i + 1)));

    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.seasonNumber, 1);
    expect(episodes.first.showRef, show.ref);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isFalse);
    expect(playback.streams, isEmpty);
    stdout.writeln('HPI S1E1 playback: ${playback.availability.name} (${playback.message})');
  }, skip: skip);

  test('a film, a news show and a themed-season show behave', () async {
    final film = (await provider.search('aquaman')).firstWhere((t) => t.title == 'Aquaman');
    expect(film.kind, ReplayKind.movie);
    expect((await provider.title(film.ref))!.year, 2018);
    final filmPlayback = await provider.playback(film.ref);
    stdout.writeln('Aquaman playback: ${filmPlayback.availability.name}');
    expect(filmPlayback.isPlayable, isFalse);

    final news = (await provider.search('jt 20h')).firstWhere((t) => t.ref == const ReplayRef('tf1plus', 'jt-20h'));
    final seasons = await provider.children(news.ref);
    expect(seasons, hasLength(1));
    final episodes = await provider.children(seasons.single.ref);
    expect(episodes, isNotEmpty);
    final newsPlayback = await provider.playback(episodes.first.ref);
    stdout.writeln('JT 20h newest playback: ${newsPlayback.availability.name}');
    expect(newsPlayback.isPlayable, isFalse);

    final koh = (await provider.search('koh lanta')).firstWhere((t) => t.title == 'Koh-Lanta');
    final kohSeasons = await provider.children(koh.ref);
    final numbers = kohSeasons.map((s) => s.seasonNumber!).toList();
    expect(numbers, orderedEquals([...numbers]..sort()));
    expect(numbers, contains(34));
    stdout.writeln('Koh-Lanta seasons: ${kohSeasons.map((s) => '${s.seasonNumber}=${s.title}').join(', ')}');
  }, skip: skip);

  test(
    'no playback outcome over a sample of programmes is a stream',
    () async {
      final counts = <ReplayAvailability, int>{};
      for (final section in ['series', 'lci', 'jeunesse', 'infos-magazines-sport', 'films']) {
        final programmes = (await provider.listing(section)).titles.take(5);
        for (final programme in programmes) {
          final seasons = await provider.children(programme.ref);
          final ReplayRef target;
          if (seasons.isEmpty) {
            target = programme.ref;
          } else {
            final episodes = await provider.children(seasons.last.ref);
            if (episodes.isEmpty) continue;
            target = episodes.last.ref;
          }
          final playback = await provider.playback(target);
          counts.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
          expect(playback.isPlayable, isFalse, reason: programme.ref.toString());
          expect(playback.streams, isEmpty);
        }
      }
      stdout.writeln('Outcomes over the sample: $counts');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
