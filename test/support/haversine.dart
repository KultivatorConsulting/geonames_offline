// An independent great-circle distance, so that tests do not check the
// resolver's arithmetic against itself.

import 'dart:math' as math;

import 'package:geonames_offline/src/resolver.dart' show earthRadiusMetres;

/// Haversine distance in metres between two points given in degrees, on the
/// same sphere the resolver uses.
double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = math.pi / 180;
  final dLat = (lat2 - lat1) * r;
  final dLon = (lon2 - lon1) * r;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * r) * math.cos(lat2 * r) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusMetres * math.asin(math.sqrt(a));
}
