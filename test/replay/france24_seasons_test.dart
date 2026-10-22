import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/france24/france24_numbering.dart';

import 'france24_recorded_api.dart';

ReplayRef _ref(String id) => ReplayRef('france24', id);

/// 42 editions ten days apart, ending on the recorded newest one: two pages that straddle New Year.
List<DateTime> _tenDayHistory() => everyNthDay(DateTime.utc(2026, 10, 16), 42, 10);

/// One edition a day for 1000 days: 48 pages over three calendar years.
List<DateTime> _dailyHistory() => everyNthDay(DateTime.utc(2026, 10, 16), 1000, 1);

RecordedFrance24 _serverWith(List<DateTime> days, {Set<int> withoutVideo = const {}}) =>
    RecordedFrance24()..histories[avecJudith] = historyOn(avecJudith, days, withoutVideo: withoutVideo);

void main() {
  group('France 24 numbering', () {
    test('the day is read from the end of an edition id', () {
      expect(france24DayOfNid('WBMZ705617-F24-FR-20261016'), DateTime.utc(2026, 10, 16));
      expect(france24DayOfNid('WBMZ1-F24-FR-20240229'), DateTime.utc(2024, 2, 29));
    });

    test('ids without a real date have no day', () {
      expect(france24DayOfNid('WBMZ1-F24-FR-20261340'), isNull);
      expect(france24DayOfNid('WBMZ1-F24-FR-20230229'), isNull);
      expect(france24DayOfNid('98A51402-A25F-4F73-89FE-DBD48F620CD9'), isNull);
      expect(france24DayOfNid(''), isNull);
    });

    test('the episode number is the day of the year', () {
      expect(france24DayOfYear(DateTime.utc(2026)), 1);
      expect(france24DayOfYear(DateTime.utc(2026, 10, 16)), 289);
      expect(france24DayOfYear(DateTime.utc(2026, 12, 31)), 365);
      expect(france24DayOfYear(DateTime.utc(2024, 12, 31)), 366);
    });
  });

  group('France24Provider seasons', () {
    test('a short history gives one season per year, oldest first', () async {
      final seasons = await providerOver(_serverWith(_tenDayHistory())).children(_ref(avecJudith));
      expect(seasons.map((s) => s.title), ['2025', '2026']);
      expect(seasons.map((s) => s.seasonNumber), [2025, 2026]);
      expect(seasons.every((s) => s.kind == ReplayKind.season), isTrue);
      expect(seasons.every((s) => s.showRef == _ref(avecJudith) && s.showTitle == 'Avec Judith'), isTrue);
      expect(seasons.first.ref, _ref('$avecJudith/2025'));
    });

    test('a history of up to three pages is read in full', () async {
      final server = _serverWith(_tenDayHistory());
      await providerOver(server).children(_ref(avecJudith));
      expect(server.editionRequests, 2);
    });

    test('a season takes the poster of its show', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      final show = (await provider.title(_ref(avecJudith)))!;
      final season = (await provider.children(_ref(avecJudith))).first;
      expect(season.posterUrl, show.posterUrl);
      expect(season.backdropUrl, show.backdropUrl);
    });

    test('a long history is bounded by its first and last page', () async {
      final server = _serverWith(_dailyHistory());
      final seasons = await providerOver(server).children(_ref(avecJudith));
      expect(seasons.map((s) => s.seasonNumber), [2024, 2025, 2026]);
      expect(server.editionRequests, 2);
    });

    test('a year with only text articles is not a season', () async {
      final days = _tenDayHistory();
      final withoutVideo = {
        for (var i = 0; i < days.length; i++)
          if (days[i].year == 2025) i,
      };
      final seasons = await providerOver(_serverWith(days, withoutVideo: withoutVideo)).children(_ref(avecJudith));
      expect(seasons.map((s) => s.seasonNumber), [2026]);
    });

    test('a programme without editions has no seasons', () async {
      expect(await providerOver(_serverWith(const [])).children(_ref(avecJudith)), isEmpty);
    });

    test('a season is found by its id and an absent year is not', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      expect((await provider.title(_ref('$avecJudith/2026')))!.seasonNumber, 2026);
      expect(await provider.title(_ref('$avecJudith/1999')), isNull);
    });
  });

  group('France24Provider episodes', () {
    test('a season lists its year in broadcast order', () async {
      final days = _tenDayHistory();
      final episodes = await providerOver(_serverWith(days)).children(_ref('$avecJudith/2026'));
      final expected = days.where((d) => d.year == 2026).toList().reversed.toList();
      expect(episodes.map((e) => e.airDate!.toUtc().day), everyElement(inInclusiveRange(1, 31)));
      expect(episodes, hasLength(expected.length));
      expect(episodes.map((e) => e.episodeNumber), expected.map(france24DayOfYear));
      expect(episodes.last.episodeNumber, 289);
    });

    test('an episode knows its show, season and numbers', () async {
      final episodes = await providerOver(_serverWith(_tenDayHistory())).children(_ref('$avecJudith/2025'));
      final first = episodes.first;
      expect(first.kind, ReplayKind.episode);
      expect(first.seasonNumber, 2025);
      expect(first.episodeNumber, france24DayOfYear(DateTime.utc(2025, 9)));
      expect(first.showRef, _ref(avecJudith));
      expect(first.seasonRef, _ref('$avecJudith/2025'));
      expect(first.ref.nativeId, startsWith('$avecJudith/e/EDITION'));
      expect(first.durationSeconds, isNotNull);
    });

    test('the other year is not mixed into a season', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      final in2025 = await provider.children(_ref('$avecJudith/2025'));
      final in2026 = await provider.children(_ref('$avecJudith/2026'));
      expect(in2025.every((e) => e.airDate!.year == 2025), isTrue);
      expect(in2025.length + in2026.length, 42);
    });

    test('text articles are not episodes', () async {
      final days = _tenDayHistory();
      final episodes = await providerOver(_serverWith(days, withoutVideo: {0, 1})).children(_ref('$avecJudith/2026'));
      expect(episodes, hasLength(days.where((d) => d.year == 2026).length - 2));
    });

    test('an edition without a timestamp is dated by its id', () async {
      final server = RecordedFrance24()
        ..histories[avecJudith] = [editionOn(avecJudith, DateTime.utc(2026, 3, 5), 0, created: false)];
      final episode = (await providerOver(server).children(_ref('$avecJudith/2026'))).single;
      expect(episode.airDate, DateTime.utc(2026, 3, 5));
      expect(episode.episodeNumber, 64);
    });

    test('two editions of one day share a number and keep their order', () async {
      final day = DateTime.utc(2026, 5, 12);
      final server = RecordedFrance24()
        ..histories[avecJudith] = [editionOn(avecJudith, day, 2), editionOn(avecJudith, day, 1)];
      final episodes = await providerOver(server).children(_ref('$avecJudith/2026'));
      expect(episodes, hasLength(2));
      expect(episodes.map((e) => e.episodeNumber).toSet(), {132});
      expect(episodes.first.ref.nativeId, contains('EDITION1-'));
    });

    test('a year with no editions is empty', () async {
      final provider = providerOver(_serverWith(_dailyHistory()));
      expect(await provider.children(_ref('$avecJudith/2023')), isEmpty);
      expect(await provider.children(_ref('$avecJudith/2030')), isEmpty);
    });

    test('a full old year is found without reading the newer pages', () async {
      final server = _serverWith(_dailyHistory());
      final episodes = await providerOver(server).children(_ref('$avecJudith/2025'));
      expect(episodes, hasLength(365));
      expect(episodes.first.episodeNumber, 1);
      expect(episodes.last.episodeNumber, 365);
      expect(server.editionRequests, lessThan(30));
    });

    test('the oldest year ends at the last page', () async {
      final days = _dailyHistory();
      final episodes = await providerOver(_serverWith(days)).children(_ref('$avecJudith/2024'));
      expect(episodes, hasLength(days.where((d) => d.year == 2024).length));
    });
  });

  group('France24Provider deep editions', () {
    test('an old edition is found by bisection and plays', () async {
      final days = _dailyHistory();
      final server = _serverWith(days);
      final oldest = server.histories[avecJudith]!.last['nid'] as String;
      final playback = await providerOver(server).playback(_ref('$avecJudith/e/$oldest'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.label, '1080p');
      expect(server.editionRequests, lessThanOrEqualTo(10));
    });

    test('an old edition can be opened with its numbers', () async {
      final server = _serverWith(_dailyHistory());
      final target = server.histories[avecJudith]![500]['nid'] as String;
      final episode = (await providerOver(server).title(_ref('$avecJudith/e/$target')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.seasonNumber, episode.airDate!.year);
      expect(episode.seasonRef, _ref('$avecJudith/${episode.seasonNumber}'));
    });

    test('an edition of the right day but another id is not found', () async {
      final provider = providerOver(_serverWith(_dailyHistory()));
      const missing = 'WBMZ1-F24-FR-20250601';
      expect(await provider.title(_ref('$avecJudith/e/$missing')), isNull);
      expect((await provider.playback(_ref('$avecJudith/e/$missing'))).availability, ReplayAvailability.expired);
    });

    test('an edition id without a date cannot be found', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      expect(await provider.title(_ref('$avecJudith/e/not-a-date')), isNull);
    });

    test('an edition before the first one of the programme is not found', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      expect(await provider.title(_ref('$avecJudith/e/WBMZ1-F24-FR-20200101')), isNull);
    });

    test('an edition after the newest one is not found', () async {
      final provider = providerOver(_serverWith(_tenDayHistory()));
      expect(await provider.title(_ref('$avecJudith/e/WBMZ1-F24-FR-20271231')), isNull);
    });
  });
}
