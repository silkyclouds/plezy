const ardImageHost = 'https://api.ardmediathek.de/image-service/';

// The resizer snaps to its own widths; beyond 1280 the files grow without a visible gain on a card.
const _widths = [320, 640, 960, 1280];
const _widthPlaceholder = '{width}';

bool isArdImage(String reference) => reference.startsWith(ardImageHost);

/// Fills the `{width}` placeholder of an image reference with the smallest width that covers [width].
///
/// The height follows from the aspect ratio the reference was published for, so [height] is not needed.
String ardImageUrl(String reference, {int? width, int? height}) {
  final wanted = width ?? 640;
  final chosen = _widths.firstWhere((candidate) => candidate >= wanted, orElse: () => _widths.last);
  return reference.replaceAll(_widthPlaceholder, '$chosen');
}
