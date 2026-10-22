/// Where the CDN serves a flagged video, as far as its URL says.
enum ArdRegion { worldwide, dach, germany }

const _dachCountries = {'DE', 'AT', 'CH'};

// Path markers of the CDNs that put the licence region in the URL. They are hints, not rules: the flag on the
// item decides whether a region applies at all.
final _germanyMarkers = [
  RegExp('/geo/de/'),
  RegExp('geoavailability_d(?!ach)'),
  RegExp('mdrgeohls'),
  RegExp('zdfvod[^/]*/.*/mp4/de/'),
];
final _dachMarkers = [RegExp('/geo/de-at-ch/'), RegExp('/dach/'), RegExp('geoavailability_dach')];

/// The region a video is licensed for.
///
/// [flagged] is the item's `isGeoBlocked`. A flagged video whose URL names no region is taken as DACH, so that
/// viewers in Austria and Switzerland are not turned away on a guess. A manifest hosted by ARTE plays everywhere
/// even when flagged.
ArdRegion ardRegionOf(Uri? stream, {required bool flagged}) {
  if (!flagged || stream == null) return ArdRegion.worldwide;
  if (stream.host.contains('arte')) return ArdRegion.worldwide;
  final text = stream.toString().toLowerCase();
  if (_dachMarkers.any((marker) => marker.hasMatch(text))) return ArdRegion.dach;
  if (_germanyMarkers.any((marker) => marker.hasMatch(text))) return ArdRegion.germany;
  return ArdRegion.dach;
}

/// Whether a viewer in [country] (ISO 3166 alpha-2) may watch a video licensed for [region].
bool ardRegionAllows(ArdRegion region, String country) => switch (region) {
  ArdRegion.worldwide => true,
  ArdRegion.dach => _dachCountries.contains(country.toUpperCase()),
  ArdRegion.germany => country.toUpperCase() == 'DE',
};
