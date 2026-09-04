// Shared check that a decoded dataset's record order is a valid implicit k-d
// tree, as spatialOrder() in the generator promises and the resolver relies on.

import 'dart:typed_data';

import 'package:geonames_offline/src/format.dart';
import 'package:geonames_offline/src/trig.dart';

/// Counts records that violate the implicit k-d tree invariant: within every
/// range `[lo, hi)`, entries before the median `(lo + hi) >> 1` must not sort
/// after it on the range's axis, and entries after it must not sort before
/// it, with ties broken by geonameId exactly as the generator breaks them.
int spatialOrderViolations(DecodedDataset d) {
  final n = d.length;
  final xs = Float64List(n);
  final ys = Float64List(n);
  final zs = Float64List(n);
  for (var i = 0; i < n; i++) {
    final v = unitVectorE7(d.latE7[i], d.lonE7[i]);
    xs[i] = v.x;
    ys[i] = v.y;
    zs[i] = v.z;
  }
  var violations = 0;
  void check(int lo, int hi, int depth) {
    if (hi - lo <= 1) return;
    final axis = depth % 3;
    final coord = axis == 0 ? xs : (axis == 1 ? ys : zs);
    final m = (lo + hi) >> 1;
    int compare(int a, int b) {
      final c = coord[a].compareTo(coord[b]);
      return c != 0 ? c : d.geonameIds[a].compareTo(d.geonameIds[b]);
    }

    for (var i = lo; i < m; i++) {
      if (compare(i, m) > 0) violations++;
    }
    for (var i = m + 1; i < hi; i++) {
      if (compare(i, m) < 0) violations++;
    }
    check(lo, m, depth + 1);
    check(m + 1, hi, depth + 1);
  }

  check(0, n, 0);
  return violations;
}
