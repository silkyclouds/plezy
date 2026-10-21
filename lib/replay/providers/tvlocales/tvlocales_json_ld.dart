import 'dart:convert';

final _block = RegExp(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', dotAll: true, caseSensitive: false);

/// Every JSON-LD object embedded in a page, flattening arrays. Blocks that are not valid JSON are skipped.
List<Map<String, dynamic>> readJsonLd(String html) {
  final objects = <Map<String, dynamic>>[];
  for (final match in _block.allMatches(html)) {
    final Object? decoded;
    try {
      decoded = jsonDecode(match.group(1)!);
    } on FormatException {
      continue;
    }
    if (decoded is Map<String, dynamic>) objects.add(decoded);
    if (decoded is List) objects.addAll(decoded.whereType<Map<String, dynamic>>());
  }
  return objects;
}

/// The first object whose `@type` is one of [types], in the order of [types].
Map<String, dynamic>? jsonLdOfType(List<Map<String, dynamic>> objects, List<String> types) {
  for (final type in types) {
    for (final object in objects) {
      if (object['@type'] == type) return object;
    }
  }
  return null;
}

/// A string field that may be given as a string or as a list of strings.
String? firstString(Object? value) {
  if (value is String) return value;
  if (value is List && value.isNotEmpty && value.first is String) return value.first as String;
  return null;
}
