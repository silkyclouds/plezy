import 'package:flutter/services.dart';

Future<AssetManifest>? _manifest;

/// Whether the app bundles a logo for the broadcaster [sourceId].
///
/// A line of text must show the full channel name when there is no logo, while the shared logo widget cuts the name
/// to the width of a logo.
Future<bool> replayLogoIsBundled(String sourceId, {AssetBundle? bundle}) async {
  final manifest = await (_manifest ??= AssetManifest.loadFromAssetBundle(bundle ?? rootBundle));
  return manifest.listAssets().contains('assets/replay/logos/$sourceId.png');
}
