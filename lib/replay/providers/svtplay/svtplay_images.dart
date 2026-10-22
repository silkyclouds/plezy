const _host = 'https://www.svtstatic.se/image/';

/// Widths worth asking for, so neighbouring requests share a cached file. The server accepts any width.
const _widths = [320, 480, 640, 960, 1280, 1920];

bool isSvtPlayImage(String reference) => reference.startsWith(_host);

/// The artwork reference for an image object `{id, changed}`, or null when the title has none.
///
/// The reference is a complete URL; [svtPlayImageUrl] only swaps the width. No `format=auto`: without it
/// the server answers JPEG, which every platform decodes, while `auto` may send AVIF.
String? svtPlayImageReference(Object? image) {
  if (image is! Map) return null;
  final id = image['id'];
  final changed = image['changed'];
  if (id == null) return null;
  final version = changed == null ? '' : '/$changed';
  return '${_host}custom/640/$id$version';
}

/// Sets the width segment of a reference to the smallest width that covers [width].
String svtPlayImageUrl(String reference, {int? width, int? height}) {
  if (!isSvtPlayImage(reference) || width == null) return reference;
  final size = _widths.firstWhere((w) => w >= width, orElse: () => _widths.last);
  return reference.replaceFirst(RegExp(r'/custom/\d+/'), '/custom/$size/');
}
