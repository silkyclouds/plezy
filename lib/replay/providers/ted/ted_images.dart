/// Hosts that serve TED artwork. Only `pi.tedcdn.com/r/` resizes, so the other host is fetched through it.
const _resizer = 'pi.tedcdn.com';
const _originals = 'pe.tedcdn.com';
const _maxWidth = 1920;

bool isTedImage(String reference) {
  final host = Uri.tryParse(reference)?.host;
  return host == _resizer || host == _originals;
}

/// Adds the `w` parameter of the resizer. Height follows the aspect ratio of the picture.
String tedImageUrl(String reference, {int? width, int? height}) {
  final uri = Uri.tryParse(reference);
  if (uri == null) return reference;
  final wrapped = uri.host == _originals ? Uri.parse('https://$_resizer/r/$_originals${uri.path}') : uri;
  if (!wrapped.path.startsWith('/r/')) return wrapped.toString();
  if (width == null || width <= 0) return wrapped.toString();
  final query = {...wrapped.queryParameters, 'w': '${width.clamp(1, _maxWidth)}'};
  return wrapped.replace(queryParameters: query).toString();
}

/// The first picture whose aspect ratio name is in [ratios], tried in order; the first picture when none matches.
String? tedPickImage(Object? images, List<String> ratios) {
  if (images is! List) return null;
  final sets = images.whereType<Map<String, dynamic>>().where((i) => i['url'] is String).toList();
  if (sets.isEmpty) return null;
  for (final ratio in ratios) {
    for (final image in sets) {
      if (image['aspectRatioName'] == ratio) return image['url'] as String;
    }
  }
  return sets.first['url'] as String;
}
