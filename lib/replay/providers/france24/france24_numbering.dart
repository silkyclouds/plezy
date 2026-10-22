/// France 24 numbers nothing: seasons and episodes are derived from the calendar day of an edition.
///
/// A season is the year, an episode is the day of that year, so two editions of one day share a number
/// but numbers always follow broadcast order and can be computed from a single edition.
final _daySuffix = RegExp(r'-(\d{4})(\d{2})(\d{2})$');

/// The calendar day encoded at the end of an edition id (`...-20261016`), or null when there is none.
DateTime? france24DayOfNid(String nid) {
  final match = _daySuffix.firstMatch(nid);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

/// 1 for January 1st through 365 or 366.
int france24DayOfYear(DateTime day) => day.difference(DateTime.utc(day.year)).inDays + 1;

/// Last instant of the calendar day [day] falls on, in UTC.
DateTime france24EndOfDay(DateTime day) => DateTime.utc(day.year, day.month, day.day, 23, 59, 59, 999);

/// Last instant of [year], in UTC.
DateTime france24EndOfYear(int year) => DateTime.utc(year, 12, 31, 23, 59, 59, 999);
