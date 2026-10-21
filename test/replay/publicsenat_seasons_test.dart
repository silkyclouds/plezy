import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_models.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_seasons.dart';

PsCard _card(String title, DateTime? date, {int number = 1}) =>
    PsCard(videoId: 'k$title', title: title, showSlug: 's', imageUrl: 'i', airDate: date, siteNumber: number);

List<String> _titles(PsSeason season) => [for (final e in season.episodes) e.card.title];

List<int?> _numbers(PsSeason season) => [for (final e in season.episodes) e.number];

void main() {
  test('a season runs from September to August', () {
    expect(broadcastSeasonStart(DateTime.utc(2026, 8, 31)), 2025);
    expect(broadcastSeasonStart(DateTime.utc(2026, 9, 1)), 2026);
    expect(broadcastSeasonStart(DateTime.utc(2026, 1, 15)), 2025);
  });

  test('cards split into seasons that run oldest to newest', () {
    final seasons = groupIntoSeasons([
      _card('d', DateTime.utc(2026, 10, 1)),
      _card('c', DateTime.utc(2026, 6, 1)),
      _card('b', DateTime.utc(2025, 12, 1)),
      _card('a', DateTime.utc(2025, 9, 5)),
    ], complete: true);
    expect(seasons.map((s) => s.startYear), [2025, 2026]);
    expect(_titles(seasons.first), ['a', 'b', 'c']);
    expect(_numbers(seasons.first), [1, 2, 3]);
    expect(_numbers(seasons.last), [1]);
  });

  test('cards listed out of date order are still numbered by date', () {
    final seasons = groupIntoSeasons([
      _card('old', DateTime.utc(2026, 1, 1)),
      _card('new', DateTime.utc(2026, 3, 1)),
    ], complete: true);
    expect(_titles(seasons.single), ['old', 'new']);
  });

  test('cards of the same day keep the site order, newest listed first', () {
    final day = DateTime.utc(2026, 3, 1);
    final seasons = groupIntoSeasons([_card('second', day), _card('first', day)], complete: true);
    expect(_titles(seasons.single), ['first', 'second']);
  });

  test('a programme with only e0 cards gets seasons without numbers', () {
    final seasons = groupIntoSeasons([
      _card('b', DateTime.utc(2026, 3, 1), number: 0),
      _card('a', DateTime.utc(2025, 3, 1), number: 0),
    ], complete: true);
    expect(seasons.map((s) => s.startYear), [2024, 2025]);
    expect(seasons.expand(_numbers), [null, null]);
  });

  test('a cut-short listing leaves the oldest season unnumbered', () {
    final seasons = groupIntoSeasons([
      _card('c', DateTime.utc(2026, 10, 1)),
      _card('b', DateTime.utc(2026, 6, 1)),
      _card('a', DateTime.utc(2026, 5, 1)),
    ], complete: false);
    expect(_numbers(seasons.first), [null, null]);
    expect(_numbers(seasons.last), [1]);
  });

  test('a card without a date joins the season of the next older card', () {
    final seasons = groupIntoSeasons([
      _card('new', DateTime.utc(2026, 10, 1)),
      _card('undated', null),
      _card('old', DateTime.utc(2025, 10, 1)),
    ], complete: true);
    expect(seasons.map(_titles), [
      ['old', 'undated'],
      ['new'],
    ]);
  });

  test('no cards give no seasons', () {
    expect(groupIntoSeasons(const [], complete: true), isEmpty);
  });
}
