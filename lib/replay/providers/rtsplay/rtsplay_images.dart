import '../srg/srg_images.dart';

const _imageHost = 'https://img.rts.ch/';

/// Widths worth asking the image server for, so neighbouring requests share a cached file.
const _widths = [160, 320, 448, 640, 960, 1280, 1920];

final _ratioSuffix = RegExp(r'/(16x9|2x3|1x1)$');

bool isRtsPlayImage(String reference) => reference.startsWith(_imageHost) || isSrgFallbackImage(reference);

/// Adds the crop and width segments the image server understands to an `img.rts.ch` reference.
///
/// A reference that already names its crop keeps it: the show poster is stored as `.../2x3`, an item
/// picture as `.../16x9`. The generic fallback pictures cannot be resized and are returned as given.
String rtsPlayImageUrl(String reference, {int? width, int? height}) {
  if (!reference.startsWith(_imageHost)) return reference;
  final ratio = _ratioSuffix.firstMatch(reference)?.group(1);
  final portrait = width != null && height != null && height > width;
  final crop = ratio ?? (portrait ? '2x3' : '16x9');
  final base = ratio == null ? reference : reference.substring(0, reference.length - ratio.length - 1);
  final wanted = width ?? (crop == '16x9' ? 640 : 320);
  return '$base/$crop/scale/width/${srgWidthBucket(_widths, wanted)}';
}

/// Artwork of RTS Play.
class RtsPlayImages implements SrgImageResizer {
  const RtsPlayImages();

  @override
  bool owns(String reference) => isRtsPlayImage(reference);

  @override
  String url(String reference, {int? width, int? height}) => rtsPlayImageUrl(reference, width: width, height: height);
}
