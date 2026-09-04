// The adversarial corpus: every case TESTING.md names, run against the
// purpose-built fixture and asserting on geonameId throughout. The fixture
// holds four Wellingtons, a place on the far side of the antimeridian, places
// near both poles, and a pair exactly equidistant from the origin: it is
// constructed so that a wrong answer has somewhere to go.

import 'dart:io';
import 'dart:typed_data';

import 'package:geonames_offline/geonames_offline.dart';
import 'package:geonames_offline/src/format.dart';
import 'package:geonames_offline/src/generator.dart';
import 'package:test/test.dart';

import 'support/haversine.dart';

const _dir = 'test/fixtures/geonames';
final _cities = File('$_dir/cities_fixture.txt').readAsStringSync();
final _admin1 = File('$_dir/admin1CodesASCII.txt').readAsStringSync();
final _countryInfo = File('$_dir/countryInfo.txt').readAsStringSync();

Uint8List _bytes({String? cities, Set<String>? countries}) => generateDataset(
  citiesTsv: cities ?? _cities,
  admin1CodesTsv: _admin1,
  countryInfoTsv: _countryInfo,
  sourceName: 'cities_fixture',
  countries: countries,
).bytes;

GeonamesReverseGeocoder _geocoder({String? cities, Set<String>? countries}) =>
    GeonamesReverseGeocoder.fromBytes(
      _bytes(cities: cities, countries: countries),
    );

void main() {
  final g = _geocoder();

  group('duplicate names across countries', () {
    // What would have to break: the fixture losing its confusables, which
    // would quietly turn every other test in this file into decoration.
    test('the fixture holds several Wellingtons, so a name proves nothing', () {
      final d = decodeDataset(_bytes());
      final wellingtons = [
        for (var i = 0; i < d.length; i++)
          if (d.names[i] == 'Wellington') d.placeAt(i),
      ];
      expect(
        wellingtons.map((p) => p.countryCode),
        unorderedEquals(['NZ', 'ZA', 'US', 'GB']),
      );
      expect(wellingtons.map((p) => p.geonameId).toSet(), hasLength(4));
    });

    // What would have to break: resolution by position, or identity.
    test('each resolves by position to its own id', () {
      expect(g.nearest(-41.29, 174.78)!.place.geonameId, 2179537); // NZ
      expect(g.nearest(-33.64, 19.01)!.place.geonameId, 90000001); // ZA
      expect(g.nearest(37.26, -97.37)!.place.geonameId, 90000002); // US
      expect(g.nearest(50.98, -3.22)!.place.geonameId, 90000003); // GB
    });
  });

  // What would have to break: a radius policy creeping in, or the distance
  // conversion.
  test('rural point with nothing nearby still answers, with the distance', () {
    final hit = g.nearest(-25, 135)!; // central Australia
    expect(hit.place.geonameId, 2193733, reason: 'Auckland is the nearest');
    final expected = haversine(-25, 135, -36.84853, 174.76349);
    expect(expected, greaterThan(3000000), reason: 'sanity: over 3,000 km');
    expect(hit.distanceMetres, closeTo(expected, 0.01));
  });

  group('equidistant between two places', () {
    // Twin West (90000008) at (0, -1) and Twin East (90000009) at (0, 1) are
    // exactly equidistant from (0, 0): mirror images, so their chord
    // distances are bit-identical, not merely close.
    test('the lower geonameId wins', () {
      final hit = g.nearest(0, 0)!;
      expect(hit.place.geonameId, 90000008);
      expect(hit.place.name, 'Twin West');
      expect(hit.distanceMetres, closeTo(haversine(0, 0, 0, -1), 0.01));
    });

    // What would have to break: the tie-break depending on position or on
    // insertion order rather than on the id. Swapping the ids must swap the
    // winner.
    test('and it is the id that decides, not position or order', () {
      final swapped = _cities
          .replaceAll('90000008', 'SWAP')
          .replaceAll('90000009', '90000008')
          .replaceAll('SWAP', '90000009');
      final hit = _geocoder(cities: swapped).nearest(0, 0)!;
      expect(hit.place.geonameId, 90000008);
      expect(hit.place.name, 'Twin East');
    });
  });

  group('antimeridian', () {
    const waitangi = (-43.95353, -176.55973);

    // What would have to break: longitude wrap-around. A planar distance
    // would see 179.9 and -176.56 as 356 degrees apart and answer Wellington.
    test('a point just west of 180 resolves across it', () {
      final hit = g.nearest(-43.9, 179.9)!;
      expect(hit.place.geonameId, 90000004, reason: 'Waitangi, Chatham Is.');
      expect(
        hit.distanceMetres,
        closeTo(haversine(-43.9, 179.9, waitangi.$1, waitangi.$2), 0.01),
      );
      expect(hit.distanceMetres, lessThan(300000));
    });

    test('and a point just east of it resolves back across', () {
      final hit = g.nearest(-43.9, -179.9)!;
      expect(hit.place.geonameId, 90000004);
      expect(
        hit.distanceMetres,
        closeTo(haversine(-43.9, -179.9, waitangi.$1, waitangi.$2), 0.01),
      );
    });

    test('longitude 180 and -180 are the same meridian', () {
      final east = g.nearest(-43.9, 180)!;
      final west = g.nearest(-43.9, -180)!;
      expect(east.place.geonameId, west.place.geonameId);
      expect(east.distanceMetres, closeTo(west.distanceMetres, 1e-6));
    });
  });

  group('poles', () {
    // What would have to break: a division by zero or NaN in the projection
    // or the distance, or pruning that mishandles the degenerate longitude.
    test('at and adjacent to the poles the answer is finite and correct', () {
      const queries = [
        (90.0, 0.0),
        (90.0, 123.4),
        (89.9999, -45.0),
        (-90.0, 0.0),
        (-90.0, 77.7),
        (-89.9999, 10.0),
      ];
      for (final (lat, lon) in queries) {
        final hit = g.nearest(lat, lon)!;
        expect(hit.distanceMetres.isFinite, isTrue, reason: '($lat, $lon)');
        expect(
          hit.distanceMetres,
          closeTo(
            haversine(lat, lon, hit.place.latitude, hit.place.longitude),
            0.01,
          ),
          reason: '($lat, $lon)',
        );
      }
      expect(
        g.nearest(90, 0)!.place.geonameId,
        90000005,
        reason: 'Longyearbyen',
      );
      expect(g.nearest(-90, 0)!.place.geonameId, 90000006, reason: 'Ushuaia');
    });

    test('longitude is irrelevant exactly at a pole', () {
      final a = g.nearest(90, 0)!;
      final b = g.nearest(90, 123.4)!;
      expect(b.place.geonameId, a.place.geonameId);
      expect(b.distanceMetres, closeTo(a.distanceMetres, 1e-6));
    });
  });

  // What would have to break: a radius policy, or an error path for "too
  // far". Correct behaviour here is easily mistaken for a bug.
  test('open ocean returns a distant coastal place, not null', () {
    final hit = g.nearest(40, -40)!; // mid North Atlantic
    expect(hit.place.geonameId, 90000003, reason: 'Wellington, Somerset');
    expect(hit.distanceMetres, greaterThan(2000000));
    expect(
      hit.distanceMetres,
      closeTo(haversine(40, -40, 50.97556, -3.22412), 0.01),
    );
  });

  // What would have to break: byId falling back to a nearest match or to
  // any other substitute. This is the case a consumer relies on to detect a
  // dangling stored reference.
  test('retired identifier: absent ids are null, never a substitute', () {
    expect(g.byId(2179537), isNotNull);
    expect(g.byId(2179538), isNull, reason: 'one past a present id');
    expect(g.byId(2179536), isNull, reason: 'one before a present id');
    expect(g.byId(0), isNull);
    expect(g.byId(-1), isNull);
    expect(g.byId(1 << 40), isNull);
  });

  test('empty dataset: nearest and byId return null rather than throwing', () {
    final empty = _geocoder(countries: {'XX'});
    expect(empty.placeCount, 0);
    expect(empty.nearest(0, 0), isNull);
    expect(empty.nearest(90, 0), isNull);
    expect(empty.byId(2179537), isNull);
  });

  group('invalid coordinates', () {
    // Documented behaviour: NaN, infinity and a latitude beyond 90 are
    // programming errors and throw; any finite longitude is wrapped.
    test('NaN, infinity and out-of-range latitude throw ArgumentError', () {
      expect(() => g.nearest(double.nan, 0), throwsArgumentError);
      expect(() => g.nearest(0, double.nan), throwsArgumentError);
      expect(() => g.nearest(double.infinity, 0), throwsArgumentError);
      expect(() => g.nearest(0, double.negativeInfinity), throwsArgumentError);
      expect(() => g.nearest(90.0000001, 0), throwsArgumentError);
      expect(() => g.nearest(-90.0000001, 0), throwsArgumentError);
    });

    test('any finite longitude is accepted and wrapped', () {
      final direct = g.nearest(-41.29, 174.78)!;
      for (final lon in [174.78 + 360, 174.78 - 360, 174.78 + 3600]) {
        final hit = g.nearest(-41.29, lon)!;
        expect(hit.place.geonameId, direct.place.geonameId, reason: '$lon');
        expect(hit.distanceMetres, closeTo(direct.distanceMetres, 1e-6));
      }
    });
  });
}
