import '../../text/html_text.dart';

/// Plain text of a title or synopsis: tags removed and named and numeric entities decoded.
///
/// The site stores curly quotes as `&#8217;` and apostrophes as `&#039;`, which the shared helper leaves alone.
String aljazeeraText(String? html) {
  final text = htmlToText(html);
  return text.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (m) {
    final code = m.group(1)!;
    final value = code.startsWith('x') ? int.tryParse(code.substring(1), radix: 16) : int.tryParse(code);
    return value == null || value <= 0 || value > 0x10FFFF ? m.group(0)! : String.fromCharCode(value);
  });
}

/// Seconds in a clock string such as `27:45`, `01:19` or `1:02:03`, or null when it is not one.
int? aljazeeraDurationSeconds(String? clock) {
  if (clock == null) return null;
  final parts = clock.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  var total = 0;
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    total = total * 60 + value;
  }
  return total;
}

/// The instant of a `date` field. The site gives UTC without a zone suffix, which Dart would read as local time.
DateTime? aljazeeraDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw);
  return DateTime.tryParse(hasZone ? raw : '${raw}Z')?.toUtc();
}
