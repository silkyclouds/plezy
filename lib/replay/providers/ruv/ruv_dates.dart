/// RÚV sends local times without an offset; Iceland keeps UTC all year, so they are read as UTC.
DateTime? ruvDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
}

/// The last instant of the day in `file_expires`. `9999-12-31` means the file never expires and gives null.
DateTime? ruvExpiry(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  if (year >= 9000) return null;
  return DateTime.utc(year, int.parse(match.group(2)!), int.parse(match.group(3)!), 23, 59, 59);
}
