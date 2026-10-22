/// Parses `dd/MM/yyyy`, optionally followed by `HH:mm` or `HH:mm:ss`, as Spanish civil time, into UTC.
DateTime? threeCatParseDate(Object? text) {
  if (text is! String) return null;
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})(?: (\d{2}):(\d{2})(?::(\d{2}))?)?$').firstMatch(text.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? '') ?? 0];
  final naive = DateTime.utc(parts[2], parts[1], parts[0], parts[3], parts[4], parts[5]);
  final summer = naive.subtract(const Duration(hours: 2));
  final inSummerTime =
      !summer.isBefore(_lastSundayAt1Utc(naive.year, 3)) && summer.isBefore(_lastSundayAt1Utc(naive.year, 10));
  return inSummerTime ? summer : naive.subtract(const Duration(hours: 1));
}

/// Daylight saving time starts and ends at 01:00 UTC on the last Sunday of March and of October.
DateTime _lastSundayAt1Utc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return lastDay.subtract(Duration(days: lastDay.weekday % 7)).add(const Duration(hours: 1));
}

/// Seconds in `HH:MM:SS:FF` (the last field counts frames) or `HH:MM:SS`; null when absent or zero.
int? threeCatParseDuration(Object? text) {
  if (text is! String) return null;
  final parts = text.trim().split(':').map(int.tryParse).toList();
  if (parts.length < 3 || parts.length > 4 || parts.any((p) => p == null)) return null;
  final seconds = parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  return seconds > 0 ? seconds : null;
}
