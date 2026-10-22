import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../replay/client/replay_api_cache.dart';
import '../../../replay/geo/replay_geo_service.dart';
import '../../../replay/provider/replay_provider_registry.dart';
import 'replay_default_sources.dart';

/// The channels to switch on for a viewer who opens catch-up TV for the first time, from the country found for
/// their connection (the stored detection is reused when it is fresh). Everything is on when the country is unknown.
Future<Set<String>> detectInitialReplaySources() async {
  final geo = ReplayGeoService(client: http.Client(), store: ReplayApiCache.instance);
  try {
    final country = await geo.resolve().timeout(const Duration(seconds: 3));
    return defaultReplaySources(replaySourceInfos, country);
  } on TimeoutException {
    return defaultReplaySources(replaySourceInfos, geo.country);
  } finally {
    geo.close();
  }
}
