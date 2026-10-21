/// Artwork hosts of the catalogue. Their URLs are signed for one size, so they are used as given.
final _imageHost = RegExp(r'^https://(images\d*\.persgroep\.net|lfvp-static-overlays\.dpgmedia\.net)/');

bool isRtlPlayImage(String reference) => _imageHost.hasMatch(reference);

/// Any change to the size segment of a signed URL makes the server answer 400, so the reference
/// is returned untouched and the player scales it.
String rtlPlayImageUrl(String reference) => reference;
