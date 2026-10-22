const _months = [
  'januar',
  'februar',
  'mars',
  'april',
  'mai',
  'juni',
  'juli',
  'august',
  'september',
  'oktober',
  'november',
  'desember',
];

/// Norwegian name of a month (1 to 12).
String nrkMonthName(int month) => _months[month - 1];

/// True when [word] is the start of a Norwegian month name, as in the "oktober" of "16. oktober".
bool nrkStartsWithMonth(String word) {
  final lower = word.trimLeft().toLowerCase();
  return _months.any(lower.startsWith);
}

final _isoDuration = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$');

/// A duration written as ISO 8601 (`PT26M22.8S`), or null.
Duration? nrkParseDuration(Object? iso) {
  if (iso is! String) return null;
  final match = _isoDuration.firstMatch(iso);
  if (match == null) return null;
  final seconds = double.tryParse(match.group(4) ?? '0') ?? 0;
  return Duration(
    days: int.tryParse(match.group(1) ?? '0') ?? 0,
    hours: int.tryParse(match.group(2) ?? '0') ?? 0,
    minutes: int.tryParse(match.group(3) ?? '0') ?? 0,
    milliseconds: (seconds * 1000).round(),
  );
}

/// A timestamp with offset as NRK writes it, or null.
DateTime? nrkParseDate(Object? iso) => iso is String ? DateTime.tryParse(iso) : null;

/// The calendar date as NRK wrote it, in Norwegian local time, whatever the viewer's own zone is.
({int year, int month, int day})? nrkLocalDate(Object? iso) {
  if (iso is! String || iso.length < 10) return null;
  final year = int.tryParse(iso.substring(0, 4));
  final month = int.tryParse(iso.substring(5, 7));
  final day = int.tryParse(iso.substring(8, 10));
  if (year == null || month == null || day == null || month < 1 || month > 12) return null;
  return (year: year, month: month, day: day);
}

/// NRK writes "no end" as the year 2100; such a date is not an expiry.
DateTime? nrkExpiry(Object? iso) {
  final date = nrkParseDate(iso);
  return date == null || date.year >= 2090 ? null : date;
}
