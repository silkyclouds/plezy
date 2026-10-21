import '../../../utils/media_server_http_client.dart';
import 'tvlocales_api.dart';
import 'tvlocales_provider.dart';
import 'tvlocales_station.dart';

const canalZoomStation = TvLocalesStation(
  id: 'canalzoom',
  name: 'Canal Zoom',
  host: 'www.canalzoom.be',
  customer: 'canalzoom',
  kind: TvLocalesSiteKind.drupal,
  latestShowSlug: 'le-jt',
);

/// Canal Zoom replays.
class CanalZoomProvider extends TvLocalesProvider {
  CanalZoomProvider(MediaServerHttpClient http) : this.withApi(TvLocalesApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  CanalZoomProvider.withApi(TvLocalesApi api) : super(canalZoomStation, api);
}
