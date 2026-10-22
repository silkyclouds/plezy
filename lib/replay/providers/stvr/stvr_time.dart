final _local = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$');

/// Reads a wall-clock time as STVR writes it ("2026-10-22 06:30:00", Slovak local time) into a UTC instant.
DateTime? stvrParseLocalTime(String? text) {
  final match = text == null ? null : _local.firstMatch(text.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? '0') ?? 0];
  final wall = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  final summerStart = _lastSundayAtOneUtc(wall.year, DateTime.march);
  final summerEnd = _lastSundayAtOneUtc(wall.year, DateTime.october);
  final inSummer = wall.subtract(const Duration(hours: 2));
  final summer = !inSummer.isBefore(summerStart) && inSummer.isBefore(summerEnd);
  return summer ? inSummer : wall.subtract(const Duration(hours: 1));
}

/// The EU clock change: the last Sunday of the month at 01:00 UTC.
DateTime _lastSundayAtOneUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % DateTime.daysPerWeek, 1);
}
