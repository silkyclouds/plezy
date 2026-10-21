/// TF1+ labels seasons "Saison 2", "Saison 34 - All Stars", a year ("2026") or a free name ("Miami"), and
/// episodes "HPI - S02 E01 - 2300 calories" or "Koh Lanta All Stars - Emission 9". The slug counters are
/// broadcast counters and disagree with the real numbers, so numbers come from labels and integer fields only.
library;

final _seasonWord = RegExp(r'^\s*saison\s+(\d+)', caseSensitive: false);
final _year = RegExp(r'^\s*(\d{4})\s*$');
final _seasonEpisode = RegExp(r'\bS(\d+)\s*E(\d+)\b', caseSensitive: false);
final _seasonWordEpisode = RegExp(
  r'(?<![\p{L}\d])saison\s+(\d+)\W+(?:épisode|episode)\s+(\d+)',
  caseSensitive: false,
  unicode: true,
);
final _episodeWord = RegExp(
  r'(?<![\p{L}\d])(?:épisode|episode|émission|emission)\s*(?:n°\s*)?(\d+)',
  caseSensitive: false,
  unicode: true,
);
final _leadingSeasonEpisode = RegExp(r'^S\d+\s*E\d+\s*(?:-\s*)?', caseSensitive: false);

/// The number a season list label states outright, or null for a themed name.
int? tf1SeasonNumberFromLabel(String label) {
  final word = _seasonWord.firstMatch(label)?.group(1);
  if (word != null) return int.parse(word);
  final year = _year.firstMatch(label)?.group(1);
  return year == null ? null : int.parse(year);
}

/// Whether a season list is a calendar year, which magazines use instead of seasons.
bool tf1IsYearLabel(String label) => _year.hasMatch(label);

/// Numbers for a show's season lists, in the order given.
///
/// Lists that state a number keep it. The others take their position in the list, skipping numbers
/// already used, so a show of themed seasons is still numbered 1..n.
List<int> tf1SeasonNumbers(List<String> labels) {
  final stated = [for (final label in labels) tf1SeasonNumberFromLabel(label)];
  final used = {...stated.whereType<int>()};
  return [for (var i = 0; i < labels.length; i++) stated[i] ?? _nextFree(i + 1, used)];
}

int _nextFree(int start, Set<int> used) {
  var n = start;
  while (used.contains(n)) {
    n++;
  }
  used.add(n);
  return n;
}

/// Season and episode a label spells out, when it does.
({int? season, int? episode}) tf1NumbersFromLabel(String label) {
  final both = _seasonEpisode.firstMatch(label) ?? _seasonWordEpisode.firstMatch(label);
  if (both != null) return (season: int.parse(both.group(1)!), episode: int.parse(both.group(2)!));
  final episode = _episodeWord.firstMatch(label)?.group(1);
  return (season: null, episode: episode == null ? null : int.parse(episode));
}

/// The part of a label that names the episode, without the show name or the "S02 E01" counter.
String tf1EpisodeTitle(String label, {String? programName, int? episode}) {
  var title = label.trim();
  if (programName != null && programName.isNotEmpty) {
    final prefix = '$programName - ';
    if (title.toLowerCase().startsWith(prefix.toLowerCase())) title = title.substring(prefix.length);
  }
  title = title.replaceFirst(_leadingSeasonEpisode, '').trim();
  if (title.isNotEmpty) return title;
  return episode != null && episode > 0 ? 'Épisode $episode' : label.trim();
}
