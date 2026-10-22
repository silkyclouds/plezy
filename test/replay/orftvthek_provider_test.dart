import 'orftvthek_browse_cases.dart';
import 'orftvthek_catalog_cases.dart';
import 'orftvthek_playback_cases.dart';
import 'orftvthek_unit_cases.dart';

/// Every ORF ON test runs from here, so `flutter test test/replay/orftvthek_provider_test.dart` covers the provider.
void main() {
  orfUnitCases();
  orfBrowseCases();
  orfCatalogCases();
  orfPlaybackCases();
}
