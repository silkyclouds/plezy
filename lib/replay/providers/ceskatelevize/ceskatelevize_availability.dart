final _until = RegExp(r'do\s+(\d{1,2})\.\s*(\d{1,2})\.');
final _minutes = RegExp(r'(\d+)\s*min');
final _hours = RegExp(r'(\d+)\s*h');

/// The end of the day named by a card label such as "Dostupné do 24. 10.".
///
/// The label carries no year, so the nearest such day that is not already over is taken. The day ends at midnight
/// Prague time, written here as 21:59:59 UTC (summer time).
DateTime? ceskatelevizeAvailableUntil(String? label, DateTime now) {
  final match = label == null ? null : _until.firstMatch(label);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final utc = now.toUtc();
  var end = DateTime.utc(utc.year, month, day, 21, 59, 59);
  if (end.isBefore(utc.subtract(const Duration(days: 2)))) end = DateTime.utc(utc.year + 1, month, day, 21, 59, 59);
  return end;
}

/// Seconds in a label such as "95 min" or "1 h 35 min", or null when it holds neither.
int? ceskatelevizeDurationSeconds(String? label) {
  if (label == null) return null;
  final hours = int.tryParse(_hours.firstMatch(label)?.group(1) ?? '');
  final minutes = int.tryParse(_minutes.firstMatch(label)?.group(1) ?? '');
  if (hours == null && minutes == null) return null;
  return ((hours ?? 0) * 60 + (minutes ?? 0)) * 60;
}
