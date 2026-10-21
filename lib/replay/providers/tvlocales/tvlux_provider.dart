import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const tvluxStation = TvLocalesStation(
  id: 'tvlux',
  name: 'TV Lux',
  host: 'www.tvlux.be',
  customer: 'tvlux',
  kind: TvLocalesSiteKind.tvlux,
  latestShowSlug: 'jt',
);

/// TV Lux replays.
class TvLuxProvider extends TvLocalesProvider {
  TvLuxProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  TvLuxProvider.withApi(TvLocalesApi api) : super(tvluxStation, api);
}
