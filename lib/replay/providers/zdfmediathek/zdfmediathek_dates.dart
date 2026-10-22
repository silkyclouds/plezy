/// ZDF writes local dates as `dd.MM.yyyy HH:mm` in Berlin time, and puts calendar dates in titles.
final _localDate = RegExp(r'^\s*(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?\s*$');
final _numericTitleDate = RegExp(r'(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{4})(?!\d)');
final _longTitleDate = RegExp(
  r'(?<!\d)(\d{1,2})\.\s*(Januar|Februar|März|Maerz|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s+(\d{4})(?!\d)',
  caseSensitive: false,
  unicode: true,
);

const _months = [
  'januar',
  'februar',
  'märz',
  'april',
  'mai',
  'juni',
  'juli',
  'august',
  'september',
  'oktober',
  'november',
  'dezember',
];

/// Parses a Berlin-time `dd.MM.yyyy[ HH:mm]` string to UTC, or null when it is not one.
DateTime? zdfLocalDate(Object? text) {
  if (text is! String) return null;
  final match = _localDate.firstMatch(text);
  if (match == null) return null;
  final day = _calendarDay(int.parse(match.group(3)!), int.parse(match.group(2)!), int.parse(match.group(1)!));
  if (day == null) return null;
  final hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '') ?? 0;
  return _berlinToUtc(day.add(Duration(hours: hour, minutes: minute)));
}

/// Parses an ISO 8601 instant such as `2027-03-04T23:59:00.000+01:00` to UTC, or null.
DateTime? zdfIsoDate(Object? text) => text is String ? DateTime.tryParse(text)?.toUtc() : null;

/// The calendar day a title names ("vom 21. Oktober 2026", "20:00 Uhr, 21.10.2026"), as midnight UTC, or null.
DateTime? zdfTitleDate(String? title) {
  if (title == null) return null;
  final long = _longTitleDate.firstMatch(title);
  if (long != null) {
    final month = _months.indexOf(long.group(2)!.toLowerCase().replaceAll('maerz', 'märz')) + 1;
    return _calendarDay(int.parse(long.group(3)!), month, int.parse(long.group(1)!));
  }
  final numeric = _numericTitleDate.firstMatch(title);
  if (numeric == null) return null;
  return _calendarDay(int.parse(numeric.group(3)!), int.parse(numeric.group(2)!), int.parse(numeric.group(1)!));
}

/// 1 for January 1st through 365 or 366.
int zdfDayOfYear(DateTime day) => day.difference(DateTime.utc(day.year)).inDays + 1;

DateTime? _calendarDay(int year, int month, int day) {
  if (month < 1 || month > 12) return null;
  final date = DateTime.utc(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

/// Central European time: UTC+1, or UTC+2 from the last Sunday of March to the last Sunday of October (01:00 UTC).
DateTime _berlinToUtc(DateTime wallClock) {
  final summerStart = _lastSundayAtOneUtc(wallClock.year, 3);
  final summerEnd = _lastSundayAtOneUtc(wallClock.year, 10);
  final asSummer = wallClock.subtract(const Duration(hours: 2));
  final inSummer = !asSummer.isBefore(summerStart) && asSummer.isBefore(summerEnd);
  return inSummer ? asSummer : wallClock.subtract(const Duration(hours: 1));
}

DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % DateTime.daysPerWeek, 1);
}
