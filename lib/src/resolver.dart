/// The GeoNames-backed [ReverseGeocoder].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'data/cities15000.dart';
import 'format.dart';
import 'reverse_geocoder.dart';
import 'trig.dart';

/// Radius of the sphere on which distances are measured, in metres: the IUGG
/// mean Earth radius. Every `distanceMetres` this package reports is a
/// great-circle distance on this sphere.
const double earthRadiusMetres = 6371008.8;

const double _degreesToRadians = math.pi / 180;

/// A [ReverseGeocoder] over a dataset in the package's binary format.
///
/// Construction decodes the whole dataset into memory and computes a unit
/// vector per place. The spatial index is the record order itself (see
/// FORMAT.md), so there is nothing else to build; the bundled dataset loads in
/// roughly ten milliseconds ahead-of-time compiled. Instances hold no mutable
/// state that a caller can observe and can be shared freely.
final class GeonamesReverseGeocoder implements ReverseGeocoder {
  /// Decodes a dataset produced by the generator.
  ///
  /// Throws [FormatException] if [bytes] is not one.
  GeonamesReverseGeocoder.fromBytes(Uint8List bytes)
    : this._(decodeDataset(bytes));

  /// The bundled `cities15000` dataset: every place GeoNames lists with a
  /// population of 15,000 or more, worldwide.
  factory GeonamesReverseGeocoder.cities15000() =>
      GeonamesReverseGeocoder.fromBytes(cities15000DatasetBytes());

  GeonamesReverseGeocoder._(this._data)
    : _xs = Float64List(_data.length),
      _ys = Float64List(_data.length),
      _zs = Float64List(_data.length) {
    for (var i = 0; i < _data.length; i++) {
      final v = unitVectorE7(_data.latE7[i], _data.lonE7[i]);
      _xs[i] = v.x;
      _ys[i] = v.y;
      _zs[i] = v.z;
    }
  }

  final DecodedDataset _data;
  final Float64List _xs;
  final Float64List _ys;
  final Float64List _zs;

  late final Map<int, int> _indexById = {
    for (var i = 0; i < _data.length; i++) _data.geonameIds[i]: i,
  };

  /// The number of places in the dataset.
  int get placeCount => _data.length;

  @override
  String get datasetVersion => _data.datasetVersion;

  @override
  String get attribution => _data.attribution;

  /// The nearest place to the point, or `null` if the dataset is empty.
  ///
  /// [latitude] must be finite and within ±90. [longitude] must be finite;
  /// any value is accepted and wrapped into ±180, so 190 means -170. An
  /// invalid coordinate is a programming error and throws [ArgumentError]
  /// rather than returning `null`, which is reserved for "nothing to find".
  ///
  /// When two places are exactly equidistant, the one with the lower
  /// [GeoPlace.geonameId] wins, so the answer is a pure function of the query
  /// and the dataset.
  @override
  NearestPlace? nearest(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) {
      throw ArgumentError(
        'Coordinates must be finite, got ($latitude, $longitude)',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'must be within ±90');
    }
    final n = _data.length;
    if (n == 0) return null;

    final wrapped = (longitude + 180) % 360 - 180;
    final q = unitVectorRad(
      latitude * _degreesToRadians,
      wrapped * _degreesToRadians,
    );
    final qx = q.x;
    final qy = q.y;
    final qz = q.z;
    final ids = _data.geonameIds;

    var best = double.infinity;
    var bestIndex = -1;

    void search(int lo, int hi, int depth) {
      if (lo >= hi) return;
      final m = (lo + hi) >> 1;
      final dx = _xs[m] - qx;
      final dy = _ys[m] - qy;
      final dz = _zs[m] - qz;
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < best || (d2 == best && ids[m] < ids[bestIndex])) {
        best = d2;
        bestIndex = m;
      }
      final axis = depth % 3;
      final diff = axis == 0
          ? qx - _xs[m]
          : (axis == 1 ? qy - _ys[m] : qz - _zs[m]);
      if (diff < 0) {
        search(lo, m, depth + 1);
        if (diff * diff <= best) search(m + 1, hi, depth + 1);
      } else {
        search(m + 1, hi, depth + 1);
        if (diff * diff <= best) search(lo, m, depth + 1);
      }
    }

    search(0, n, 0);
    return NearestPlace(
      place: _data.placeAt(bestIndex),
      distanceMetres: chordToMetres(math.sqrt(best)),
    );
  }

  @override
  GeoPlace? byId(int geonameId) {
    final i = _indexById[geonameId];
    return i == null ? null : _data.placeAt(i);
  }
}

/// Converts a chord length between two unit vectors to the great-circle
/// distance between the points, in metres, on a sphere of [earthRadiusMetres].
double chordToMetres(double chord) =>
    2 * earthRadiusMetres * math.asin(math.min(1.0, chord / 2));
