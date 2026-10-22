/// Every picture lives under this prefix; the part after it is the path the catalogue reports.
const nfbImageHost = 'https://assets.nfbcdn.ca/medias/norman/';

const _defaultWidth = 720;
const _maxWidth = 2048;

bool isNfbImage(String reference) => reference.startsWith(nfbImageHost);

/// A reference for a path such as `thumbs_xlarge/2024/ryan_keyart_16x9.jpg`, or null when the catalogue gave none.
String? nfbImageFromPath(Object? path) {
  if (path is! String || path.trim().isEmpty) return null;
  return Uri.encodeFull('$nfbImageHost${path.trim()}');
}

/// A reference for a full picture address as pages print it, with the size query the page asked for removed.
String? nfbImageFromUrl(String? url) {
  if (url == null || !url.startsWith(nfbImageHost)) return null;
  final end = url.indexOf(RegExp(r'[?#]'));
  return end < 0 ? url : url.substring(0, end);
}

/// The picture resized by the site's own resizer. Giving the width alone keeps the aspect ratio.
String nfbImageUrl(String reference, {int? width, int? height}) {
  final bare = nfbImageFromUrl(reference);
  if (bare == null) return reference;
  final key = width == null && height != null ? 'h' : 'w';
  final wanted = key == 'h' ? height! : (width ?? _defaultWidth);
  return '$bare?$key=${wanted.clamp(1, _maxWidth)}';
}
