/// Artwork is served from signed URLs: the signature covers the size, so a width can only be chosen
/// among the ones the API listed, never computed.
const franceTvImageHost = 'https://medias.france.tv/';

const _separator = '|';

bool isFranceTvImage(String reference) => reference.startsWith(franceTvImageHost);

/// Packs the signed URLs of one picture, smallest first, into one reference string.
///
/// The first URL is also valid on its own, so a consumer that ignores [franceTvImageUrl] still gets a picture.
String? franceTvImageReference(Object? images, List<String> preferredTypes) {
  if (images is! List) return null;
  for (final type in preferredTypes) {
    for (final image in images.whereType<Map<String, dynamic>>()) {
      if (image['type'] != type) continue;
      final sized = _sizedUrls(image['urls']);
      if (sized.isNotEmpty) return sized.map((e) => e.$2).join(_separator);
    }
  }
  return null;
}

/// Picks the smallest listed width that covers [width], or the largest one when none does.
String franceTvImageUrl(String reference, {int? width, int? height}) {
  final sized = reference.split(_separator).map((u) => (_widthOf(u), u)).toList();
  if (sized.length == 1) return sized.single.$2;
  sized.sort((a, b) => a.$1.compareTo(b.$1));
  final wanted = width ?? 800;
  return sized.firstWhere((e) => e.$1 >= wanted, orElse: () => sized.last).$2;
}

List<(int, String)> _sizedUrls(Object? urls) {
  if (urls is! Map) return const [];
  final sized = [
    for (final url in urls.values.whereType<String>())
      if (isFranceTvImage(url)) (_widthOf(url), url),
  ];
  sized.sort((a, b) => a.$1.compareTo(b.$1));
  return sized;
}

final _sizeSegment = RegExp(r'/(\d+)x\d+/');

int _widthOf(String url) => int.tryParse(_sizeSegment.firstMatch(url)?.group(1) ?? '') ?? 0;
