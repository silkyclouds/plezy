/// Typed reads from decoded gateway JSON, where any field may be missing or of another type.
Map<String, dynamic>? ardMap(Object? value) => value is Map<String, dynamic> ? value : null;

List<Map<String, dynamic>> ardMaps(Object? value) => [
  if (value is List)
    for (final entry in value)
      if (entry is Map<String, dynamic>) entry,
];

/// A trimmed, non-empty string, or null.
String? ardText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? ardInt(Object? value) => value is num ? value.toInt() : (value is String ? int.tryParse(value) : null);

DateTime? ardDate(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;
