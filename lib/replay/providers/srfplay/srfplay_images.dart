import '../srg/srg_images.dart';

const _originHost = 'https://download-media.srf.ch/';
const _resizer = 'https://il.srgssr.ch/images/';

/// Widths the SRG image resizer accepts.
const _widths = [240, 320, 480, 720, 960, 1920];

bool isSrfPlayImage(String reference) =>
    reference.startsWith(_originHost) || reference.startsWith(_resizer) || isSrgFallbackImage(reference);

/// Routes an SRF picture through the SRG resizer, because the file server itself cannot scale.
///
/// Pictures that are already resized, and the generic fallback pictures, are returned as given.
String srfPlayImageUrl(String reference, {int? width, int? height}) {
  if (!reference.startsWith(_originHost)) return reference;
  final portrait = width != null && height != null && height > width;
  final size = srgWidthBucket(_widths, width ?? (portrait ? 320 : 480));
  return '$_resizer?imageUrl=${Uri.encodeQueryComponent(reference)}&format=webp&width=$size';
}

/// Artwork of SRF Play.
class SrfPlayImages implements SrgImageResizer {
  const SrfPlayImages();

  @override
  bool owns(String reference) => isSrfPlayImage(reference);

  @override
  String url(String reference, {int? width, int? height}) => srfPlayImageUrl(reference, width: width, height: height);
}
