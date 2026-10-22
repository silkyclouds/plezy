import 'zdfmediathek_dates.dart';

/// Season and episode of a video as ZDF gives them or implies them.
typedef ZdfNumbers = ({int? season, int? episode});

final _infoline = RegExp(r'(?<![\p{L}\d])S(\d{1,4})\s+F(\d{1,4})(?!\d)', unicode: true);
final _episodeAfterWord = RegExp(r'(?<!\p{L})Folge\s+(\d{1,4})(?!\d)', caseSensitive: false, unicode: true);
final _episodeBeforeWord = RegExp(r'(?<![\p{L}\d])(\d{1,4})\.\s*Folge(?!\p{L})', caseSensitive: false, unicode: true);
final _seasonAfterWord = RegExp(r'(?<!\p{L})Staffel\s+(\d{1,3})(?!\d)', caseSensitive: false, unicode: true);
final _seasonBeforeWord = RegExp(r'(?<![\p{L}\d])(\d{1,3})\.\s*Staffel(?!\p{L})', caseSensitive: false, unicode: true);

/// Reads the numbers of one video teaser or document.
///
/// The structured `seasonNumber` and `episodeNumber` win (they arrive as strings, sometimes zero padded, and a
/// season may be a year). Otherwise the `S17 F01` tag of the info line is read, then the title ("Folge 4",
/// "2. Staffel"), then the name of the cluster the video sits in ("Staffel 3 - alle Folgen").
ZdfNumbers zdfNumbers(Map<String, dynamic> item, {String? clusterName}) {
  var season = _positive(item['seasonNumber']);
  var episode = _positive(item['episodeNumber']);
  if (season != null && episode != null) return (season: season, episode: episode);

  final tag = _infoline.firstMatch(((item['infoline'] as Map?)?['title'] as String?) ?? '');
  if (tag != null) {
    season ??= _positive(tag.group(1));
    episode ??= _positive(tag.group(2));
  }
  final title = item['titel'] as String? ?? '';
  episode ??= _firstNumber(title, [_episodeAfterWord, _episodeBeforeWord]);
  season ??= _firstNumber(title, [_seasonAfterWord, _seasonBeforeWord]);
  season ??= _firstNumber(clusterName ?? '', [_seasonAfterWord, _seasonBeforeWord]);
  return (season: season, episode: episode);
}

/// Position of a daily programme that carries only a date in its title: the year is the season and the day of that
/// year is the episode, so numbers follow broadcast order and can be computed from one edition alone.
ZdfNumbers? zdfNumbersFromTitleDate(Map<String, dynamic> item) {
  final day = zdfTitleDate(item['titel'] as String?);
  return day == null ? null : (season: day.year, episode: zdfDayOfYear(day));
}

int? _positive(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

int? _firstNumber(String text, List<RegExp> patterns) {
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return _positive(match.group(1));
  }
  return null;
}
