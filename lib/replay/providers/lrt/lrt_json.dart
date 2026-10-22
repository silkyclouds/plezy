import 'dart:convert';

/// A JSON object from a response body that may already be decoded or still be text. Anything else is null.
Map<String, dynamic>? lrtJsonObject(Object? body) {
  final value = body is String ? _decode(body) : body;
  return value is Map<String, dynamic> ? value : null;
}

/// The objects of a JSON list; entries of another shape are dropped.
List<Map<String, dynamic>> lrtJsonObjects(Object? value) {
  if (value is! List) return const [];
  return [...value.whereType<Map<String, dynamic>>()];
}

/// A trimmed, non-empty string, or null.
String? lrtString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? lrtInt(Object? value) {
  if (value is num) return value.toInt();
  return value is String ? int.tryParse(value.trim()) : null;
}

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}
