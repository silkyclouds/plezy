import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const antenneCentreStation = TvLocalesStation(
  id: 'antennecentre',
  name: 'Antenne Centre',
  host: 'www.antennecentre.tv',
  customer: 'actv',
  kind: TvLocalesSiteKind.drupal,
  latestShowSlug: 'le-18-dix-huit',
);

/// Antenne Centre replays.
class AntenneCentreProvider extends TvLocalesProvider {
  AntenneCentreProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  AntenneCentreProvider.withApi(TvLocalesApi api) : super(antenneCentreStation, api);
}
