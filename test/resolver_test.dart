// The resolver's happy path, input validation, and a brute-force cross-check
// of the spatial search at full scale. The adversarial cases are in
// corpus_test.dart. What would have to break here: the search, the pruning,
// the distance conversion, id lookup, or argument validation.

import 'dart:io';
import 'dart:math' as math;

import 'package:geonames_offline/geonames_offline.dart';
import 'package:geonames_offline/src/data/cities15000.dart';
import 'package:geonames_offline/src/format.dart';
import 'package:geonames_offline/src/generator.dart';
import 'package:test/test.dart';

import 'support/haversine.dart';

const _dir = 'test/fixtures/geonames';

GeonamesReverseGeocoder _fixture({Set<String>? countries}) =>
    GeonamesReverseGeocoder.fromBytes(
      generateDataset(
        citiesTsv: File('$_dir/cities_fixture.txt').readAsStringSync(),
        admin1CodesTsv: File('$_dir/admin1CodesASCII.txt').readAsStringSync(),
        countryInfoTsv: File('$_dir/countryInfo.txt').readAsStringSync(),
        sourceName: 'cities_fixture',
        countries: countries,
      ).bytes,
    );

void main() {
  group('against the fixture', () {
    final g = _fixture();

    test('resolves each Wellington by position, not by name', () {
      expect(g.nearest(-41.29, 174.78)!.place.geonameId, 2179537);
      expect(g.nearest(-33.64, 19.01)!.place.geonameId, 90000001);
      expect(g.nearest(37.26, -97.37)!.place.geonameId, 90000002);
      expect(g.nearest(50.98, -3.22)!.place.geonameId, 90000003);
    });

    test('reports the great-circle distance in metres', () {
      final hit = g.nearest(-41.29, 174.78)!;
      final expected = haversine(-41.29, 174.78, -41.28664, 174.77557);
      expect(expected, greaterThan(400), reason: 'sanity: a few hundred m');
      expect(hit.distanceMetres, closeTo(expected, 0.001));

      final far = g.nearest(-33.64, 19.01)!;
      expect(
        far.distanceMetres,
        closeTo(haversine(-33.64, 19.01, -33.63981, 19.00867), 0.001),
      );
    });

    test('exposes the place fields verbatim', () {
      final place = g.nearest(-41.29, 174.78)!.place;
      expect(place.name, 'Wellington');
      expect(place.countryCode, 'NZ');
      expect(place.countryName, 'New Zealand');
      expect(place.admin1Code, 'G2');
      expect(place.admin1Name, 'Wellington');
      expect(place.latitude, -41.28664);
      expect(place.longitude, 174.77557);
    });

    test('byId finds a present id and returns null for an absent one', () {
      expect(g.byId(2179537)?.name, 'Wellington');
      expect(g.byId(2179537)?.countryCode, 'NZ');
      expect(g.byId(90000003)?.countryCode, 'GB');
      expect(g.byId(1), isNull);
      expect(g.byId(-2179537), isNull);
      expect(g.byId(0), isNull);
    });

    test('passes through the dataset version and attribution', () {
      expect(g.datasetVersion, 'cities_fixture 2025-06-10 (13 places)');
      expect(g.attribution, geonamesAttribution);
      expect(g.placeCount, 13);
    });

    test('wraps any longitude into ±180', () {
      final direct = g.nearest(-41.29, 174.78)!;
      for (final lon in [174.78 + 360, 174.78 - 360, 174.78 + 720]) {
        final wrapped = g.nearest(-41.29, lon)!;
        expect(wrapped.place.geonameId, direct.place.geonameId);
        expect(wrapped.distanceMetres, closeTo(direct.distanceMetres, 1e-6));
      }
    });

    test('rejects coordinates that are not coordinates', () {
      expect(() => g.nearest(double.nan, 0), throwsArgumentError);
      expect(() => g.nearest(0, double.nan), throwsArgumentError);
      expect(() => g.nearest(double.infinity, 0), throwsArgumentError);
      expect(() => g.nearest(0, double.negativeInfinity), throwsArgumentError);
      expect(() => g.nearest(90.0001, 0), throwsArgumentError);
      expect(() => g.nearest(-91, 0), throwsArgumentError);
      expect(g.nearest(90, 0), isNotNull, reason: 'the pole itself is valid');
      expect(g.nearest(-90, 0), isNotNull);
    });
  });

  test('an empty dataset answers null, not an error', () {
    final g = _fixture(countries: {'XX'});
    expect(g.placeCount, 0);
    expect(g.nearest(-41.29, 174.78), isNull);
    expect(g.byId(2179537), isNull);
    expect(g.datasetVersion, 'cities_fixture XX (0 places)');
  });

  group('against the bundled dataset', () {
    late final GeonamesReverseGeocoder g;
    late final List<GeoPlace> places;
    setUpAll(() {
      final watch = Stopwatch()..start();
      g = GeonamesReverseGeocoder.cities15000();
      printOnFailure('cities15000() took ${watch.elapsedMilliseconds} ms');
      final data = decodeDataset(cities15000DatasetBytes());
      places = [for (var i = 0; i < data.length; i++) data.placeAt(i)];
    });

    test('loads and answers a well-known query', () {
      expect(g.placeCount, greaterThan(25000));
      expect(g.placeCount, places.length);
      expect(g.nearest(-41.29, 174.78)!.place.geonameId, 2179537);
      expect(g.nearest(-36.85, 174.76)!.place.geonameId, 2193733);
      expect(g.byId(2179537)?.name, 'Wellington');
    });

    test('the indexed search agrees with a linear scan everywhere', () {
      final random = math.Random(2179537);
      final queries = <(double, double)>[
        (90, 0),
        (-90, 0),
        (89.9999, 123),
        (-89.9999, -45),
        (0, 180),
        (0, -180),
        (-43.9, 179.99),
        (-43.9, -179.99),
        (0, 0),
        for (var i = 0; i < 400; i++)
          (random.nextDouble() * 180 - 90, random.nextDouble() * 360 - 180),
      ];
      for (final (lat, lon) in queries) {
        var bestDistance = double.infinity;
        for (final p in places) {
          final d = haversine(lat, lon, p.latitude, p.longitude);
          if (d < bestDistance) bestDistance = d;
        }
        // Anything within a millimetre of the best is an acceptable answer:
        // the two distance formulas differ by rounding, and exact ties are
        // the corpus's business, not this test's.
        final acceptable = {
          for (final p in places)
            if (haversine(lat, lon, p.latitude, p.longitude) <=
                bestDistance + 1e-3)
              p.geonameId,
        };
        final hit = g.nearest(lat, lon)!;
        expect(
          acceptable,
          contains(hit.place.geonameId),
          reason: 'query ($lat, $lon)',
        );
        expect(
          hit.distanceMetres,
          closeTo(bestDistance, 1e-3),
          reason: 'query ($lat, $lon)',
        );
      }
    });
  });
}
