/// Generic pictures the image service hands out when a show has none of its own. They cannot be resized.
const srgFallbackImageHost = 'https://il.srgssr.ch/image-service/';

bool isSrgFallbackImage(String reference) => reference.startsWith(srgFallbackImageHost);

/// The smallest of [widths] that is at least [wanted], so neighbouring requests share a cached file.
int srgWidthBucket(List<int> widths, int wanted) => widths.firstWhere((w) => w >= wanted, orElse: () => widths.last);

/// Builds sized picture URLs for the image server of one business unit.
abstract interface class SrgImageResizer {
  bool owns(String reference);

  String url(String reference, {int? width, int? height});
}
