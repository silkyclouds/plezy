import 'orftvthek_json.dart';

/// A season and episode number a title states about itself.
typedef OrfMarkers = ({int? season, int? episode});

final _seasonAndEpisode = RegExp(r'\bS(\d{1,2})\s*[/-]?\s*E(\d{1,3})\b');
final _germanSeasonAndEpisode = RegExp(r'\bStaffel\s+(\d{1,3})\W+Folge\s+(\d{1,4})\b', caseSensitive: false);
final _counter = RegExp(r'\(\s*(\d{1,3})\s*/\s*(\d{1,3})\s*\)');
final _folge = RegExp(r'\bFolge\s+(\d{1,4})\b', caseSensitive: false);
final _seasonWord = RegExp(r'\b(?:Staffel|Periode|Season)\s+(\d{1,3})\s*$', caseSensitive: false);
final _seasonSuffix = RegExp(r'^(.*?\S)[\s,:–-]*\b(?:Staffel|Periode|Season)\s+(\d{1,3})\s*$', caseSensitive: false);

/// What a title says about its place in a show: "(S4/E3)", "Staffel 2, Folge 5", "Show (4/12): Name" or "Folge 284".
///
/// A bare "(4/12)" is read as episode 4 of 12 only when the first number is not above the second, which keeps
/// dates and scores out.
OrfMarkers orfTitleMarkers(String title) {
  final both = _seasonAndEpisode.firstMatch(title) ?? _germanSeasonAndEpisode.firstMatch(title);
  if (both != null) return (season: int.parse(both.group(1)!), episode: int.parse(both.group(2)!));
  final counter = _counter.firstMatch(title);
  if (counter != null) {
    final number = int.parse(counter.group(1)!);
    if (number > 0 && number <= int.parse(counter.group(2)!)) return (season: null, episode: number);
  }
  final folge = _folge.firstMatch(title);
  return (season: null, episode: folge == null ? null : int.parse(folge.group(1)!));
}

/// The season number a text such as an episode's sub-headline ("Staffel 3") ends with.
int? orfSeasonFromText(String? text) {
  final match = text == null ? null : _seasonWord.firstMatch(text.trim());
  return match == null ? null : int.parse(match.group(1)!);
}

/// A profile title split into the show and its season: "Kiwi Staffel 2" is season 2 of "Kiwi".
({String show, int season})? splitOrfSeasonTitle(String profileTitle) {
  final match = _seasonSuffix.firstMatch(profileTitle.trim());
  if (match == null) return null;
  final show = match.group(1)!.trim();
  return show.isEmpty ? null : (show: show, season: int.parse(match.group(2)!));
}

/// An episode with the number it gets in its season, or null when it is an extra without one.
typedef OrfNumbered = ({Map<String, dynamic> episode, int? number});

/// Numbers the episodes of ONE season and returns them in viewing order.
///
/// ORF gives no numbers as fields. When at least half of the episodes state a distinct number in their title those
/// numbers are used and the rest (trailers, making-ofs) stay unnumbered at the end. Otherwise the episodes are
/// numbered by broadcast date, oldest first, which is the order a viewer watches them in.
List<OrfNumbered> orfNumberEpisodes(List<Map<String, dynamic>> episodes) {
  final stated = [for (final e in episodes) orfTitleMarkers(orfString(e['title']) ?? '').episode];
  final present = stated.whereType<int>().toList();
  final usable =
      present.isNotEmpty && present.length * 2 >= episodes.length && present.toSet().length == present.length;
  final order = _byDate(episodes);
  if (!usable) {
    return [for (var rank = 0; rank < order.length; rank++) (episode: episodes[order[rank]], number: rank + 1)];
  }
  final ranked = [for (var rank = 0; rank < order.length; rank++) (index: order[rank], rank: rank)];
  ranked.sort((a, b) {
    final left = stated[a.index];
    final right = stated[b.index];
    if (left != null && right != null) return left.compareTo(right);
    if (left == null && right == null) return a.rank.compareTo(b.rank);
    return left == null ? 1 : -1;
  });
  return [for (final r in ranked) (episode: episodes[r.index], number: stated[r.index])];
}

/// Indexes of [episodes] from oldest to newest; episodes broadcast together keep the order of their ids.
List<int> _byDate(List<Map<String, dynamic>> episodes) {
  final order = List<int>.generate(episodes.length, (i) => i);
  order.sort((a, b) {
    final left = orfDate(episodes[a]['date']);
    final right = orfDate(episodes[b]['date']);
    if (left != null && right != null) {
      final byDate = left.compareTo(right);
      if (byDate != 0) return byDate;
    }
    return (orfInt(episodes[a]['id']) ?? 0).compareTo(orfInt(episodes[b]['id']) ?? 0);
  });
  return order;
}
