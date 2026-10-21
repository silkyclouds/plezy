import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const teleMbStation = TvLocalesStation(
  id: 'telemb',
  name: 'Télé MB',
  host: 'www.telemb.be',
  customer: 'telemb',
  kind: TvLocalesSiteKind.drupal,
  latestShowSlug: 'les-infos',
);

/// Télé MB replays.
class TeleMbProvider extends TvLocalesProvider {
  TeleMbProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  TeleMbProvider.withApi(TvLocalesApi api) : super(teleMbStation, api);
}
