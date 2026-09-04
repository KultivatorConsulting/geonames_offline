/// Deterministic trigonometry for the spatial index.
///
/// The dataset's record order is a k-d tree over unit vectors computed from
/// each place's coordinates, and that order must be bit-identical wherever
/// the generator runs, or the asset is not reproducible byte for byte.
/// `dart:math`'s `sin` and `cos` defer to the platform's C library, which makes
/// no such promise, so this file carries its own, adapted from fdlibm's kernel
/// polynomials. It is accurate to a few ulps over the range it is used for,
/// `|x| <= pi`, and it is exactly symmetric — `sinRad(-x) == -sinRad(x)` and
/// `cosRad(-x) == cosRad(x)` bit for bit — which the resolver's deterministic
/// tie-breaking relies on.
library;

import 'dart:math' as math;

/// Radians per unit of a coordinate expressed in 1e-7 degrees.
const double radiansPerE7 = math.pi / 180 / 1e7;

// pi/2 split into a 33-bit head and a tail, so that k * _pio2Hi is exact for
// the small k used here (fdlibm's pio2_1 and pio2_1t).
const double _pio2Hi = 1.57079632673412561417e+00;
const double _pio2Lo = 6.07710050650619224932e-11;
const double _twoOverPi = 6.36619772367581382433e-01;

const double _s1 = -1.66666666666666324348e-01;
const double _s2 = 8.33333333332248946124e-03;
const double _s3 = -1.98412698298579493134e-04;
const double _s4 = 2.75573137070700676789e-06;
const double _s5 = -2.50507602534068634195e-08;
const double _s6 = 1.58969099521155010221e-10;

const double _c1 = 4.16666666666666019037e-02;
const double _c2 = -1.38888888888741095749e-03;
const double _c3 = 2.48015872894767294178e-05;
const double _c4 = -2.75573143513906633035e-07;
const double _c5 = 2.08757232129817482790e-09;
const double _c6 = -1.13596475577881948265e-11;

/// sin(x) for |x| <= pi/4.
double _kernelSin(double x) {
  final z = x * x;
  final v = z * x;
  final r = _s2 + z * (_s3 + z * (_s4 + z * (_s5 + z * _s6)));
  return x + v * (_s1 + z * r);
}

/// cos(x) for |x| <= pi/4.
double _kernelCos(double x) {
  final z = x * x;
  final r = z * (_c1 + z * (_c2 + z * (_c3 + z * (_c4 + z * (_c5 + z * _c6)))));
  return 1.0 - (0.5 * z - z * r);
}

/// Reduces `x` to `r` with `x = k * pi/2 + r`, `|r| <= pi/4`. Exact for the
/// `|x| <= pi` this library needs (Sterbenz: the subtraction cannot round).
(int, double) _reduce(double x) {
  final k = (x * _twoOverPi).round();
  final r = (x - k * _pio2Hi) - k * _pio2Lo;
  return (k, r);
}

/// Sine of an angle in radians, `|x| <= pi`, computed deterministically.
double sinRad(double x) {
  final (k, r) = _reduce(x);
  return switch (k & 3) {
    0 => _kernelSin(r),
    1 => _kernelCos(r),
    2 => -_kernelSin(r),
    _ => -_kernelCos(r),
  };
}

/// Cosine of an angle in radians, `|x| <= pi`, computed deterministically.
double cosRad(double x) {
  final (k, r) = _reduce(x);
  return switch (k & 3) {
    0 => _kernelCos(r),
    1 => -_kernelSin(r),
    2 => -_kernelCos(r),
    _ => _kernelSin(r),
  };
}

/// The unit vector of a position on the sphere, from coordinates in 1e-7
/// degrees. `z` points to the north pole; `x` to latitude 0, longitude 0.
({double x, double y, double z}) unitVectorE7(int latE7, int lonE7) {
  final lat = latE7 * radiansPerE7;
  final lon = lonE7 * radiansPerE7;
  final cosLat = cosRad(lat);
  return (x: cosLat * cosRad(lon), y: cosLat * sinRad(lon), z: sinRad(lat));
}
