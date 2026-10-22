import '../../text/html_text.dart';

/// Plain text for a synopsis. The site mixes HTML tags with numeric character references (`&#x27;`) that the shared
/// HTML reducer leaves alone.
String? nfbText(Object? raw) {
  if (raw is! String) return null;
  final decoded = htmlToText(raw.replaceAll('\r\n', '\n')).replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (m) {
    final code = m.group(1)!;
    final value = code.startsWith('x') ? int.tryParse(code.substring(1), radix: 16) : int.tryParse(code);
    return value == null || value <= 0 || value > 0x10FFFF ? '' : String.fromCharCode(value);
  });
  final text = decoded.replaceAll('​', '').replaceAll('﻿', '').trim();
  return text.isEmpty ? null : text;
}

/// A trimmed string, or null when it is missing or blank.
String? nfbNonEmpty(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// An integer from a JSON number or a numeric string, or null.
int? nfbInt(Object? raw) => switch (raw) {
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()),
  _ => null,
};

/// Seconds in an ISO 8601 duration such as `PT10M` or `PT01H02M03S`; the site rounds to the minute.
int? nfbIsoSeconds(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$').firstMatch(raw.trim());
  if (match == null) return null;
  final seconds =
      int.parse(match.group(1) ?? '0') * 3600 +
      int.parse(match.group(2) ?? '0') * 60 +
      (double.tryParse(match.group(3) ?? '0') ?? 0).round();
  return seconds > 0 ? seconds : null;
}

/// A catalogue timestamp as UTC. The catalogue sends no zone, so a bare time is read as UTC rather than as the
/// device's local time.
DateTime? nfbDate(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
  return DateTime.tryParse(hasZone ? text : '${text}Z')?.toUtc();
}
