import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const telesambreStation = TvLocalesStation(
  id: 'telesambre',
  name: 'Télésambre',
  host: 'www.telesambre.be',
  customer: 'telesambre',
  kind: TvLocalesSiteKind.drupal,
  latestShowSlug: 'le-jt',
);

/// Télésambre replays.
class TelesambreProvider extends TvLocalesProvider {
  TelesambreProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  TelesambreProvider.withApi(TvLocalesApi api) : super(telesambreStation, api);
}
