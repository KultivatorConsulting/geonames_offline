/// Offline reverse geocoding: coordinates in, nearest populated place out,
/// resolved against an embedded GeoNames dataset with no network access.
///
/// The contract is [ReverseGeocoder]. A [ReverseGeocoder.nearest] query is
/// answered with a [NearestPlace], and a [ReverseGeocoder.byId] lookup with a
/// [GeoPlace].
library;

export 'src/reverse_geocoder.dart';
