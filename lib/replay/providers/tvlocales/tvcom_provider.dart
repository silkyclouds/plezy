import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const tvcomStation = TvLocalesStation(
  id: 'tvcom',
  name: 'TVCOM',
  host: 'www.tvcom.be',
  customer: 'tvcom',
  kind: TvLocalesSiteKind.drupal,
  latestShowSlug: 'pedagoscope',
);

/// TVCOM replays.
class TvcomProvider extends TvLocalesProvider {
  TvcomProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  TvcomProvider.withApi(TvLocalesApi api) : super(tvcomStation, api);
}
