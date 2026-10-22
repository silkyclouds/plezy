import '../../../utils/media_server_http_client.dart';
import '../../provider/replay_provider.dart';
import '../srg/srg_api.dart';
import '../srg/srg_provider.dart';
import 'rsi_unit.dart';

/// RSI Play (Swiss Italian public television): clear HLS for the part of the catalogue licensed outside
/// Switzerland. Items flagged Swiss-only are greyed out for viewers elsewhere.
class RsiProvider extends SrgProvider implements ReplayAvailabilityPredictor {
  RsiProvider(MediaServerHttpClient http) : this.withApi(SrgApi(rsiUnit, http));

  /// Test seam: a provider over an API whose responses the caller controls.
  RsiProvider.withApi(SrgApi api) : super(rsiUnit, api);
}
