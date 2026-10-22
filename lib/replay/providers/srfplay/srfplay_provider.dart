import '../../../utils/media_server_http_client.dart';
import '../../provider/replay_provider.dart';
import '../srg/srg_api.dart';
import '../srg/srg_provider.dart';
import 'srfplay_unit.dart';

/// SRF Play (Swiss German public television): clear HLS for the part of the catalogue licensed outside
/// Switzerland. Items flagged Swiss-only are greyed out for viewers elsewhere.
class SrfPlayProvider extends SrgProvider implements ReplayAvailabilityPredictor {
  SrfPlayProvider(MediaServerHttpClient http) : this.withApi(SrgApi(srfPlayUnit, http));

  /// Test seam: a provider over an API whose responses the caller controls.
  SrfPlayProvider.withApi(SrgApi api) : super(srfPlayUnit, api);
}
