import 'publicsenat_models.dart';

/// An episode with the position derived for it, or null when the programme does not number its episodes.
class PsEpisode {
  final PsCard card;
  final int? number;

  const PsEpisode(this.card, this.number);
}

/// One broadcast season of a programme. [episodes] run from oldest to newest.
class PsSeason {
  final int startYear;
  final List<PsEpisode> episodes;

  const PsSeason(this.startYear, this.episodes);
}

/// First calendar year of the September to August broadcast season that [date] falls in.
int broadcastSeasonStart(DateTime date) => date.month >= 9 ? date.year : date.year - 1;

/// Splits a programme's cards into broadcast seasons and numbers the episodes inside each.
///
/// The site gives no season and its own `eN` counter restarts at different points for different
/// programmes, so a season is a September to August span and an episode's number is its place in the season
/// by air date. A programme whose cards are all `e0` (standalone documentaries, debates) gets seasons without
/// numbers. [newestFirst] is the order the site lists them, which breaks ties between cards of the same day.
/// When [complete] is false the oldest season is cut short, so its positions would be wrong and are left out.
List<PsSeason> groupIntoSeasons(List<PsCard> newestFirst, {required bool complete}) {
  if (newestFirst.isEmpty) return const [];
  final numbered = newestFirst.any((c) => (c.siteNumber ?? 0) > 0);
  final entries = _chronological(newestFirst.reversed.toList());

  final byYear = <int, List<PsCard>>{};
  for (final (card, date) in entries) {
    byYear.putIfAbsent(date == null ? 0 : broadcastSeasonStart(date), () => []).add(card);
  }
  final oldest = byYear.keys.first;
  return [
    for (final MapEntry(key: year, value: cards) in byYear.entries)
      PsSeason(year, [
        for (var i = 0; i < cards.length; i++)
          PsEpisode(cards[i], numbered && (complete || year != oldest) ? i + 1 : null),
      ]),
  ];
}

/// Cards ordered by air date. A card without a date takes the date of the next older card in the listing.
List<(PsCard, DateTime?)> _chronological(List<PsCard> listedOldestFirst) {
  var carried = listedOldestFirst.map((c) => c.airDate).whereType<DateTime>().firstOrNull;
  final dated = <(PsCard, DateTime?, int)>[];
  for (var i = 0; i < listedOldestFirst.length; i++) {
    carried = listedOldestFirst[i].airDate ?? carried;
    dated.add((listedOldestFirst[i], carried, i));
  }
  final epoch = DateTime.utc(1970);
  dated.sort((a, b) {
    final byDate = (a.$2 ?? epoch).compareTo(b.$2 ?? epoch);
    return byDate != 0 ? byDate : a.$3.compareTo(b.$3);
  });
  return [for (final (card, date, _) in dated) (card, date)];
}
