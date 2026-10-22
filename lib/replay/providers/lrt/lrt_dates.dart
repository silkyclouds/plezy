/// Parses an ISO timestamp, tolerating the `$D` marker the site's page payload puts in front of dates.
DateTime? lrtParseIso(Object? value) {
  if (value is! String) return null;
  final text = value.trim().replaceFirst(r'$D', '');
  return DateTime.tryParse(text)?.toUtc();
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

final _rfc822 = RegExp(
  r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|Z|GMT|UTC)?',
);

/// Parses an RSS `pubDate` such as `Thu, 22 Oct 2026 08:44:00 +0300` into UTC, or null when it is not one.
DateTime? lrtParseRfc822(String? value) {
  final match = value == null ? null : _rfc822.firstMatch(value);
  final month = _months[match?.group(2)?.toLowerCase()];
  if (match == null || month == null) return null;
  final local = DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.tryParse(match.group(6) ?? '') ?? 0,
  );
  final zone = match.group(7);
  if (zone == null || zone.length != 5) return local;
  final sign = zone.startsWith('-') ? -1 : 1;
  final offset = Duration(hours: int.parse(zone.substring(1, 3)), minutes: int.parse(zone.substring(3, 5)));
  return sign > 0 ? local.subtract(offset) : local.add(offset);
}

/// Seconds from a number or from `HH:MM:SS` / `MM:SS`.
int? lrtParseDuration(Object? value) {
  if (value is num) return value > 0 ? value.toInt() : null;
  if (value is! String) return null;
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final numbers = [for (final p in parts) int.tryParse(p)];
  if (numbers.contains(null)) return null;
  final seconds = numbers.cast<int>().fold<int>(0, (total, part) => total * 60 + part);
  return seconds > 0 ? seconds : null;
}

/// `yyyy-MM-dd HH:mm` in Lithuanian time, which is how the site dates its recordings.
String lrtLocalStamp(DateTime utc) {
  final local = utc.toUtc().add(Duration(hours: _isSummerTime(utc.toUtc()) ? 3 : 2));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

bool _isSummerTime(DateTime utc) {
  final start = _lastSundayAtOne(utc.year, 3);
  final end = _lastSundayAtOne(utc.year, 10);
  return !utc.isBefore(start) && utc.isBefore(end);
}

DateTime _lastSundayAtOne(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  final sunday = lastDay.subtract(Duration(days: lastDay.weekday % 7));
  return DateTime.utc(sunday.year, sunday.month, sunday.day, 1);
}
