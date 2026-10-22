const _imageHosts = ['https://img.3cat.cat/', 'https://statics.3cat.cat/'];

bool isThreeCatImage(String reference) => _imageHosts.any(reference.startsWith);

/// 3Cat serves each size as a separate pre-rendered file, so a reference is already the final address.
String threeCatImageUrl(String reference) => reference;

/// The artwork of one item, picked from the many pre-rendered sizes it lists.
class ThreeCatArtwork {
  final String? poster;
  final String? backdrop;
  final String? logo;

  const ThreeCatArtwork({this.poster, this.backdrop, this.logo});
}

const _backdropWidth = 670;
const _posterWidth = 300;

/// Landscape and portrait pictures by exact `mida`, then the original of the matching kind when no sized one exists.
/// Banners, tiny thumbnails and pictures with the title baked in are never chosen.
ThreeCatArtwork threeCatArtwork(Object? images) {
  final entries = [
    for (final raw in (images is List ? images : const []).whereType<Map<String, dynamic>>())
      if (raw['text'] is String) _Image(raw['text'] as String, '${raw['mida']}', '${raw['rel_name']}'.toLowerCase()),
  ];
  return ThreeCatArtwork(
    poster:
        _nearest(entries.where((e) => e.ratio != null && e.ratio! >= 0.6 && e.ratio! <= 0.75), _posterWidth) ??
        _original(entries, const ['img_poster']),
    backdrop:
        _nearest(
          entries.where((e) => e.ratio != null && e.ratio! >= 1.6 && e.ratio! <= 1.9 && e.width! >= 200),
          _backdropWidth,
        ) ??
        _original(entries, const ['imatge_169', 'keyvideo', 'image']),
    logo: _original(entries, const ['img_logo']),
  );
}

class _Image {
  final String url;
  final String size;
  final String rel;

  _Image(this.url, this.size, this.rel);

  late final RegExpMatch? _match = RegExp(r'^(\d+)x(\d+)$').firstMatch(size);

  int? get width => _match == null ? null : int.parse(_match.group(1)!);

  double? get ratio => _match == null ? null : width! / int.parse(_match.group(2)!);
}

String? _nearest(Iterable<_Image> candidates, int wanted) {
  final sorted = candidates.toList()..sort((a, b) => a.width!.compareTo(b.width!));
  if (sorted.isEmpty) return null;
  return (sorted.where((e) => e.width! >= wanted).firstOrNull ?? sorted.last).url;
}

String? _original(List<_Image> entries, List<String> rels) {
  for (final rel in rels) {
    final hit = entries.where((e) => e.size == 'MASTER' && e.rel == rel).firstOrNull;
    if (hit != null) return hit.url;
  }
  return null;
}
