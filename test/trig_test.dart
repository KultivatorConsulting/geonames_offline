// What would have to break: the range reduction, a polynomial coefficient, or
// the sign symmetry the resolver's tie-breaking relies on.

import 'dart:math' as math;

import 'package:geonames_offline/src/trig.dart';
import 'package:test/test.dart';

void main() {
  const steps = 20000;
  final sweep = [
    for (var i = 0; i <= steps; i++) -math.pi + 2 * math.pi * i / steps,
    0.0,
    math.pi / 2,
    -math.pi / 2,
    math.pi / 4,
    3 * math.pi / 4,
    math.pi,
    -math.pi,
  ];

  test('sinRad and cosRad agree with dart:math to within a few ulps', () {
    for (final x in sweep) {
      expect(sinRad(x), closeTo(math.sin(x), 1e-15), reason: 'sin($x)');
      expect(cosRad(x), closeTo(math.cos(x), 1e-15), reason: 'cos($x)');
    }
  });

  test('sinRad is exactly odd and cosRad exactly even', () {
    for (final x in sweep) {
      expect(sinRad(-x), -sinRad(x), reason: 'sin(-$x)');
      expect(cosRad(-x), cosRad(x), reason: 'cos(-$x)');
    }
  });

  test('unit vectors have unit length and point where they should', () {
    final north = unitVectorE7(900000000, 1234567);
    expect(north.z, closeTo(1, 1e-15));
    expect(north.x.abs(), lessThan(1e-15));
    expect(north.y.abs(), lessThan(1e-15));

    final origin = unitVectorE7(0, 0);
    expect(origin.x, 1.0);
    expect(origin.y, 0.0);
    expect(origin.z, 0.0);

    final wellington = unitVectorE7(-412866400, 1747755700);
    final lat = -41.28664 * math.pi / 180;
    final lon = 174.77557 * math.pi / 180;
    expect(wellington.x, closeTo(math.cos(lat) * math.cos(lon), 1e-15));
    expect(wellington.y, closeTo(math.cos(lat) * math.sin(lon), 1e-15));
    expect(wellington.z, closeTo(math.sin(lat), 1e-15));

    final random = math.Random(7);
    for (var i = 0; i < 1000; i++) {
      final v = unitVectorE7(
        random.nextInt(1800000001) - 900000000,
        random.nextInt(3600000001) - 1800000000,
      );
      expect(v.x * v.x + v.y * v.y + v.z * v.z, closeTo(1, 1e-15));
    }
  });
}
