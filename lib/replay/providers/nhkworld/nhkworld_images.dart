const nhkWorldImageHost = 'https://www3.nhk.or.jp';

bool isNhkWorldImage(String reference) => reference.startsWith('$nhkWorldImageHost/');

/// The fetchable address of an artwork path. The path carries a content hash, so the size cannot be rewritten:
/// the size is chosen when the title is mapped, by [nhkPickImage].
String nhkWorldImageUrl(String reference) => reference.startsWith('/') ? '$nhkWorldImageHost$reference' : reference;

/// The smallest image at least [minWidth] wide from a list of `{url, width, height}`, else the widest one.
String? nhkPickImage(Object? images, {required int minWidth}) {
  if (images is! List) return null;
  final candidates = [
    for (final image in images.whereType<Map<String, dynamic>>())
      if (image['url'] is String) (url: image['url'] as String, width: (image['width'] as num?)?.toInt() ?? 0),
  ]..sort((a, b) => a.width.compareTo(b.width));
  if (candidates.isEmpty) return null;
  final fit = candidates.where((image) => image.width >= minWidth).firstOrNull ?? candidates.last;
  return nhkWorldImageUrl(fit.url);
}
