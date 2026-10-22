final _stamp = RegExp(r'^(\d{2})-(\d{2})-(\d{4})(?: (\d{2}):(\d{2})(?::(\d{2}))?)?$');

/// A moment RTVE wrote as `dd-MM-yyyy HH:mm:ss` in Spanish local time, as UTC. Null for anything else.
DateTime? rtveParseDate(Object? raw) {
  if (raw is! String) return null;
  final m = _stamp.firstMatch(raw.trim());
  if (m == null) return null;
  int part(int i) => int.parse(m.group(i) ?? '0');
  final month = part(2);
  final day = part(1);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final local = DateTime.utc(part(3), month, day, part(4), part(5), part(6));
  return local.subtract(_madridOffset(local));
}

/// A moment given as epoch milliseconds, or null.
DateTime? rtveFromEpoch(Object? millis) =>
    millis is num && millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true) : null;

/// Europe/Madrid is UTC+1, and UTC+2 from the last Sunday of March to the last Sunday of October (01:00 UTC both ways).
Duration _madridOffset(DateTime localAsUtc) {
  final summerStart = _lastSundayAtOneUtc(localAsUtc.year, DateTime.march);
  final summerEnd = _lastSundayAtOneUtc(localAsUtc.year, DateTime.october);
  final asSummer = localAsUtc.subtract(const Duration(hours: 2));
  final inSummer = !asSummer.isBefore(summerStart) && asSummer.isBefore(summerEnd);
  return Duration(hours: inSummer ? 2 : 1);
}

DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % 7, 1);
}
