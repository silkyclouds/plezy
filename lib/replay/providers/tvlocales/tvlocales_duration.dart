final _isoDuration = RegExp(r'^P(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)$');
final _clockText = RegExp(r'^(?:(\d+)\s*h\s*)?(?:(\d+)\s*(?:min|m|mn|\x27)?)?$', caseSensitive: false);

/// Seconds in an ISO 8601 duration such as `PT22M4S`, or null when the text is not one.
int? parseIsoDuration(String? text) {
  final match = text == null ? null : _isoDuration.firstMatch(text.trim());
  if (match == null) return null;
  final seconds = _sum(match.group(1), 3600) + _sum(match.group(2), 60) + _sum(match.group(3), 1);
  return seconds == 0 ? null : seconds;
}

/// Seconds in the minute counts the Drupal stations print, such as `29 min` or `1 h 05`.
int? parseDurationText(String? text) {
  final match = text == null ? null : _clockText.firstMatch(text.trim());
  if (match == null) return null;
  final seconds = _sum(match.group(1), 3600) + _sum(match.group(2), 60);
  return seconds == 0 ? null : seconds;
}

int _sum(String? count, int unit) => (int.tryParse(count ?? '') ?? 0) * unit;
