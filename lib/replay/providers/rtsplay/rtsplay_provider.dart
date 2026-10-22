import '../../../utils/media_server_http_client.dart';
import '../srg/srg_api.dart';
import '../srg/srg_provider.dart';
import 'rtsplay_unit.dart';

/// RTS Play (Swiss public television): clear HLS for the part of the catalogue licensed outside Switzerland.
class RtsPlayProvider extends SrgProvider {
  RtsPlayProvider(MediaServerHttpClient http) : this.withApi(SrgApi(rtsPlayUnit, http));

  /// Test seam: a provider over an API whose responses the caller controls.
  RtsPlayProvider.withApi(SrgApi api) : super(rtsPlayUnit, api);
}
