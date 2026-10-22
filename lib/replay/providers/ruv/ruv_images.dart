import 'dart:convert';

const _host = 'https://myndir.ruv.is/';
const _maxWidth = 1920;
const _maxHeight = 2160;

bool isRuvImage(String reference) => reference.startsWith(_host);

/// Rewrites the size inside an image URL.
///
/// RÚV's image handler takes a base64 JSON recipe as the path (bucket, key, edits). The resize edit is changed and
/// the recipe is encoded again; any size is accepted. A reference that is not a recipe comes back unchanged.
String ruvImageUrl(String reference, {int? width, int? height}) {
  if (!isRuvImage(reference) || (width == null && height == null)) return reference;
  final recipe = _decode(reference.substring(_host.length));
  if (recipe == null) return reference;
  final edits = Map<String, dynamic>.from(recipe['edits'] as Map? ?? const {});
  edits['resize'] = {
    if (width != null) 'width': width.clamp(1, _maxWidth),
    if (height != null) 'height': height.clamp(1, _maxHeight),
  };
  return '$_host${base64.encode(utf8.encode(jsonEncode({...recipe, 'edits': edits})))}';
}

Map<String, dynamic>? _decode(String encoded) {
  try {
    final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(encoded))));
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}
