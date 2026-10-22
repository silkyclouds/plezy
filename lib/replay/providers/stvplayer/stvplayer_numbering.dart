final _seriesName = RegExp(r'^\s*Series\s+(\d{1,3})\s*$', caseSensitive: false);
final _episodeWord = RegExp(r'^\s*(?:Episode|Ep\.?)\s+(\d{1,4})\b', caseSensitive: false);
final _episodeCounter = RegExp(r'^\s*(\d{1,4})\.\s');
final _dateInId = RegExp(r'(?<!\d)((?:19|20)\d{2})(\d{2})(\d{2})(?!\d)');

/// The number in a series name such as "Series 18", or null for names like "Specials" or "2013".
int? stvSeasonNumberFromName(String? name) {
  final match = name == null ? null : _seriesName.firstMatch(name);
  return match == null ? null : int.parse(match.group(1)!);
}

/// Numbers the series of a programme, given their names in catalogue order.
///
/// "Series N" keeps N. Other names ("Episodes 26 - 50", "USA") follow the highest numbered series in list order. When
/// two names claim the same number the list is numbered 1..n instead, so every season keeps a distinct number.
List<int> stvSeasonNumbers(List<String> names) {
  final stated = [for (final name in names) stvSeasonNumberFromName(name)];
  final claimed = stated.whereType<int>().toList();
  if (claimed.toSet().length != claimed.length) return [for (var i = 1; i <= names.length; i++) i];
  var next = claimed.isEmpty ? 1 : claimed.reduce((a, b) => a > b ? a : b) + 1;
  return [for (final number in stated) number ?? next++];
}

/// The episode number stated in a title ("Episode 3", "Episode 3 - Marriage on the Slopes", "12. Title"), or null.
int? stvEpisodeNumberFromTitle(String? title) {
  if (title == null) return null;
  final match = _episodeWord.firstMatch(title) ?? _episodeCounter.firstMatch(title);
  return match == null ? null : int.parse(match.group(1)!);
}

/// The broadcast date written into an episode guid (`show-20261021-2240`, `...-deathtrap-20020114.mpg`), or null.
DateTime? stvAirDateFromGuid(String? guid) {
  final match = guid == null ? null : _dateInId.firstMatch(guid);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime.utc(year, month, day);
}
