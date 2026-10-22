const tvpImageHost = 'https://s.tvp.pl/images/';

final _widthSlot = RegExp(r'\{width:(\d+)\}');
final _heightSlot = RegExp(r'\{height:(\d+)\}');

bool isTvpImage(String reference) => reference.startsWith(tvpImageHost);

/// The artwork reference for one aspect of an `images` block (`16x9` or `3x4`), or null when it has none.
///
/// The site gives a template whose `{width:N}` and `{height:N}` slots hold the default size, and a protocol-relative
/// address; the reference keeps the template with an explicit scheme.
String? tvpImageReference(Object? block, String aspect) {
  final entries = block is Map ? block[aspect] : null;
  if (entries is! List) return null;
  for (final entry in entries.whereType<Map>()) {
    final raw = (entry['templateUrl'] ?? entry['url']) as String?;
    if (raw == null || raw.isEmpty) continue;
    final absolute = raw.startsWith('//') ? 'https:$raw' : raw;
    if (isTvpImage(absolute)) return absolute;
  }
  return null;
}

/// Fills the size slots. With one side given, the other follows the template's proportions; with none, the default
/// size is kept.
String tvpImageUrl(String reference, {int? width, int? height}) {
  final defaultWidth = int.tryParse(_widthSlot.firstMatch(reference)?.group(1) ?? '');
  final defaultHeight = int.tryParse(_heightSlot.firstMatch(reference)?.group(1) ?? '');
  if (defaultWidth == null || defaultHeight == null) return reference;

  var w = width ?? defaultWidth;
  var h = height ?? defaultHeight;
  if (width != null && height == null) h = (width * defaultHeight / defaultWidth).round();
  if (height != null && width == null) w = (height * defaultWidth / defaultHeight).round();
  w = w.clamp(1, 1920);
  h = h.clamp(1, 1920);
  return reference.replaceFirst(_widthSlot, '$w').replaceFirst(_heightSlot, '$h');
}
