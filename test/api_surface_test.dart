// The slice 1 acceptance check, not an accuracy test.
//
// This is the code a downstream consumer writes against the tagged API
// surface: a class of their own implementing ReverseGeocoder, and value
// objects constructed by hand. What would have to break for it to fail: any
// member of the contract being renamed, retyped, removed, or changing its
// nullability. It proves nothing about resolution — there is no resolver yet.
// See TESTING.md for the fixture discipline that applies once there is.

import 'package:geonames_offline/geonames_offline.dart';
import 'package:test/test.dart';

const _wellington = GeoPlace(
  countryCode: 'NZ',
  admin1Code: 'G2',
  geonameId: 2179537,
  name: 'Wellington',
  admin1Name: 'Wellington',
  countryName: 'New Zealand',
  latitude: -41.28664,
  longitude: 174.77557,
);

/// A consumer's stand-in: answers every query with the one place it holds.
final class _StubReverseGeocoder implements ReverseGeocoder {
  @override
  NearestPlace? nearest(double latitude, double longitude) =>
      const NearestPlace(place: _wellington, distanceMetres: 1234.5);

  @override
  GeoPlace? byId(int geonameId) =>
      geonameId == _wellington.geonameId ? _wellington : null;

  @override
  String get datasetVersion => 'stub';

  @override
  String get attribution => 'stub';
}

void main() {
  test(
    'a consumer can implement ReverseGeocoder and call it through the interface',
    () {
      final ReverseGeocoder geocoder = _StubReverseGeocoder();

      final nearest = geocoder.nearest(-41.29, 174.78);
      expect(nearest?.place.geonameId, 2179537);
      expect(nearest?.distanceMetres, 1234.5);

      expect(geocoder.byId(2179537)?.geonameId, 2179537);
      expect(geocoder.byId(1), isNull);

      expect(geocoder.datasetVersion, 'stub');
      expect(geocoder.attribution, 'stub');
    },
  );

  test('GeoPlace is const-constructible and exposes every field', () {
    expect(_wellington.countryCode, 'NZ');
    expect(_wellington.admin1Code, 'G2');
    expect(_wellington.geonameId, 2179537);
    expect(_wellington.name, 'Wellington');
    expect(_wellington.admin1Name, 'Wellington');
    expect(_wellington.countryName, 'New Zealand');
    expect(_wellington.latitude, -41.28664);
    expect(_wellington.longitude, 174.77557);
  });

  test('NearestPlace pairs a place with the distance from the query point', () {
    const nearest = NearestPlace(place: _wellington, distanceMetres: 42);

    expect(nearest.place.geonameId, 2179537);
    expect(nearest.distanceMetres, 42);
  });

  test('the admin1 fields are nullable', () {
    const place = GeoPlace(
      countryCode: 'VA',
      admin1Code: null,
      geonameId: 6691831,
      name: 'Vatican City',
      admin1Name: null,
      countryName: 'Vatican City',
      latitude: 41.90268,
      longitude: 12.45414,
    );

    expect(place.admin1Code, isNull);
    expect(place.admin1Name, isNull);
  });
}
