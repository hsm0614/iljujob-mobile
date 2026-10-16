import 'package:flutter/foundation.dart';

const _openStreetMapTileHost = 'tile.openstreetmap.org';

bool isRecoverableFlutterError(FlutterErrorDetails details) {
  if (details.silent) return true;

  return details.exceptionAsString().contains(_openStreetMapTileHost);
}
