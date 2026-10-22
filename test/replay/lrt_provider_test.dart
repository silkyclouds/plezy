import 'lrt_catalog_cases.dart';
import 'lrt_parsing_cases.dart';
import 'lrt_playback_cases.dart';

/// Every LRT test runs from here, so `flutter test test/replay/lrt_provider_test.dart` covers the provider.
void main() {
  lrtParsingCases();
  lrtCatalogCases();
  lrtPlaybackCases();
}
