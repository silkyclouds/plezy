/// Trimmed text with non-breaking spaces made plain, or null when empty. TF1+ sends empty strings
/// instead of null and uses U+00A0 inside prices and synopses.
String? tf1Text(Object? value) {
  if (value is! String) return null;
  final text = value.replaceAll(' ', ' ').trim();
  return text.isEmpty ? null : text;
}

Map<String, dynamic> tf1Map(Object? value) => value is Map<String, dynamic> ? value : const {};

int? tf1Positive(Object? value) => value is num && value > 0 ? value.toInt() : null;

DateTime? tf1Date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
