/// Images are signed per size, so a URL cannot be resized by editing it. The catalogue queries ask for the sizes
/// below and the provider hands the signed URL through unchanged.
const ceskatelevizeCardWidth = 480;
const ceskatelevizeCardHeight = 270;
const ceskatelevizePortraitWidth = 300;
const ceskatelevizeBackdropWidth = 960;
const ceskatelevizeBackdropHeight = 540;
const ceskatelevizeLogoWidth = 600;
const ceskatelevizeLogoHeight = 280;

const _imageHost = 'https://ctfs.ceskatelevize.cz/';

bool isCeskaTelevizeImage(String reference) => reference.startsWith(_imageHost);

/// The reference itself: the signature covers the size, and any other size would be refused.
String ceskatelevizeImageUrl(String reference) => reference;
