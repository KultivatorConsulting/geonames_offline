/// Turns GeoNames export files into a dataset in the package's binary format.
///
/// Everything here is deterministic: the same inputs produce the same bytes,
/// on any machine. That is what makes automated regeneration reviewable, and
/// it is a tested property, not an aspiration.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'format.dart';
import 'trig.dart';

/// The attribution stamped into every dataset the generator produces, and
/// returned by `ReverseGeocoder.attribution` for it. CC BY 4.0 requires it to
/// reach the users of an application that ships the data.
const String geonamesAttribution =
    'Contains data from GeoNames (https://www.geonames.org/), licensed under '
    'CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). The data has '
    'been filtered and repackaged for offline use.';

/// Parses `countryInfo.txt` into ISO 3166-1 alpha-2 code to country name.
Map<String, String> parseCountryInfo(String tsv) {
  final names = <String, String>{};
  var lineNo = 0;
  for (final line in const LineSplitter().convert(tsv)) {
    lineNo++;
    if (line.isEmpty || line.startsWith('#')) continue;
    final cols = line.split('\t');
    if (cols.length < 5) {
      throw FormatException(
        'countryInfo line $lineNo: expected at least 5 tab-separated columns, '
        'found ${cols.length}',
      );
    }
    names[cols[0]] = cols[4];
  }
  return names;
}

/// Parses `admin1CodesASCII.txt` into `CC.CODE` to division name.
Map<String, String> parseAdmin1Codes(String tsv) {
  final names = <String, String>{};
  var lineNo = 0;
  for (final line in const LineSplitter().convert(tsv)) {
    lineNo++;
    if (line.isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 2) {
      throw FormatException(
        'admin1 line $lineNo: expected at least 2 tab-separated columns, '
        'found ${cols.length}',
      );
    }
    names[cols[0]] = cols[1];
  }
  return names;
}

/// Feature codes the generator drops unless told otherwise: what GeoNames
/// explicitly codes as a section of a populated place (`PPLX`: Kowloon,
/// Puxi), and places that are historical, abandoned or destroyed. Sub-city
/// granularity is a documented non-goal, but GeoNames also codes many
/// sections as ordinary `PPL` rows (the Paris arrondissements), and those are
/// kept verbatim rather than guessed at.
const Set<String> defaultExcludedFeatureCodes = {
  'PPLX',
  'PPLH',
  'PPLQ',
  'PPLW',
};

/// Parses a GeoNames places export such as `cities15000.txt`.
///
/// Keeps only rows whose country code is in [countries], if given, and drops
/// rows whose feature code is in [excludeFeatureCodes]. Also reports the
/// latest `modification date` among the kept rows, which
/// [deriveDatasetVersion] uses.
({List<PlaceRecord> records, String? latestModification}) parseCities(
  String tsv, {
  Set<String>? countries,
  Set<String> excludeFeatureCodes = defaultExcludedFeatureCodes,
}) {
  final records = <PlaceRecord>[];
  final seen = <int>{};
  String? latest;
  var lineNo = 0;
  for (final line in const LineSplitter().convert(tsv)) {
    lineNo++;
    if (line.isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 19) {
      throw FormatException(
        'cities line $lineNo: expected 19 tab-separated columns, '
        'found ${cols.length}',
      );
    }
    final countryCode = cols[8];
    if (countries != null && !countries.contains(countryCode)) continue;
    if (excludeFeatureCodes.contains(cols[7])) continue;
    final id = int.tryParse(cols[0]);
    if (id == null) {
      throw FormatException('cities line $lineNo: bad geonameid "${cols[0]}"');
    }
    if (!seen.add(id)) {
      throw FormatException('cities line $lineNo: duplicate geonameid $id');
    }
    records.add(
      PlaceRecord(
        geonameId: id,
        name: cols[1],
        latE7: _parseE7(cols[4], -90, 90, lineNo, 'latitude'),
        lonE7: _parseE7(cols[5], -180, 180, lineNo, 'longitude'),
        countryCode: countryCode,
        admin1Code: cols[10].isEmpty ? null : cols[10],
      ),
    );
    final date = cols[18];
    if (latest == null || date.compareTo(latest) > 0) latest = date;
  }
  return (records: records, latestModification: latest);
}

int _parseE7(String text, double min, double max, int lineNo, String what) {
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value < min || value > max) {
    throw FormatException('cities line $lineNo: bad $what "$text"');
  }
  // Exact for up to seven decimals; GeoNames publishes five.
  return (value * 1e7).round();
}

/// The permutation that puts [records] into spatial index order: an implicit
/// k-d tree over their unit vectors, laid out in an array.
///
/// For any range `[lo, hi)`, the record at `(lo + hi) >> 1` is the split
/// node; everything in `[lo, m)` is on or below it along the split axis and
/// everything in `(m, hi)` is on or above. The axis cycles x, y, z by depth.
/// Ties on the axis are broken by ascending `geonameId`, so the order is a
/// pure function of the input set.
List<int> spatialOrder(List<PlaceRecord> records) {
  final n = records.length;
  final xs = Float64List(n);
  final ys = Float64List(n);
  final zs = Float64List(n);
  for (var i = 0; i < n; i++) {
    final v = unitVectorE7(records[i].latE7, records[i].lonE7);
    xs[i] = v.x;
    ys[i] = v.y;
    zs[i] = v.z;
  }
  final order = List<int>.generate(n, (i) => i);

  void build(int lo, int hi, int depth) {
    if (hi - lo <= 1) return;
    final axis = depth % 3;
    final coord = axis == 0 ? xs : (axis == 1 ? ys : zs);
    final range = order.sublist(lo, hi)
      ..sort((a, b) {
        final c = coord[a].compareTo(coord[b]);
        if (c != 0) return c;
        return records[a].geonameId.compareTo(records[b].geonameId);
      });
    order.setRange(lo, hi, range);
    final m = (lo + hi) >> 1;
    build(lo, m, depth + 1);
    build(m + 1, hi, depth + 1);
  }

  build(0, n, 0);
  return order;
}

/// The dataset version string for a generated dataset, derived from the
/// content rather than the clock so that regeneration is reproducible:
/// `cities15000 2026-09-03 (31722 places)`, with the country filter inserted
/// after the source name when there is one.
String deriveDatasetVersion({
  required String sourceName,
  required Set<String>? countries,
  required String? latestModification,
  required int placeCount,
}) {
  final filter = countries == null
      ? ''
      : ' ${(countries.toList()..sort()).join(',')}';
  final date = latestModification == null ? '' : ' $latestModification';
  final noun = placeCount == 1 ? 'place' : 'places';
  return '$sourceName$filter$date ($placeCount $noun)';
}

/// Builds a dataset from the contents of a GeoNames places export and the two
/// lookup tables that give divisions and countries their display names.
///
/// [sourceName] names the export in the dataset version, e.g. `cities15000`.
/// [countries] restricts the dataset to those ISO 3166-1 alpha-2 codes; case
/// is normalised. [excludeFeatureCodes] drops rows by GeoNames feature code
/// and defaults to [defaultExcludedFeatureCodes]. [datasetVersion] overrides
/// the derived version string.
///
/// Throws [FormatException] for malformed input, and for a country code that
/// `countryInfo.txt` does not know, because a place without a country name
/// would be a silent gap in the data rather than an error.
({Uint8List bytes, String datasetVersion, int placeCount}) generateDataset({
  required String citiesTsv,
  required String admin1CodesTsv,
  required String countryInfoTsv,
  required String sourceName,
  Set<String>? countries,
  Set<String> excludeFeatureCodes = defaultExcludedFeatureCodes,
  String? datasetVersion,
}) {
  final countryNames = parseCountryInfo(countryInfoTsv);
  final admin1Names = parseAdmin1Codes(admin1CodesTsv);
  final filter = countries?.map((c) => c.toUpperCase()).toSet();
  final parsed = parseCities(
    citiesTsv,
    countries: filter,
    excludeFeatureCodes: excludeFeatureCodes
        .map((c) => c.toUpperCase())
        .toSet(),
  );
  for (final r in parsed.records) {
    if (!countryNames.containsKey(r.countryCode)) {
      throw FormatException(
        'Country code "${r.countryCode}" (geonameid ${r.geonameId}) has no '
        'entry in countryInfo',
      );
    }
  }
  final order = spatialOrder(parsed.records);
  final ordered = [for (final i in order) parsed.records[i]];
  final version =
      datasetVersion ??
      deriveDatasetVersion(
        sourceName: sourceName,
        countries: filter,
        latestModification: parsed.latestModification,
        placeCount: ordered.length,
      );
  final bytes = encodeDataset(
    datasetVersion: version,
    attribution: geonamesAttribution,
    records: ordered,
    countryNames: countryNames,
    admin1Names: admin1Names,
  );
  return (bytes: bytes, datasetVersion: version, placeCount: ordered.length);
}

/// Renders [bytes] as a Dart library that embeds the dataset and exposes it
/// through a function called `<identifier>DatasetBytes()`, so that it can be
/// bundled with no asset pipeline and no file I/O. [identifier] is derived
/// from [sourceName] when not given.
String renderEmbeddedDart({
  required Uint8List bytes,
  required String sourceName,
  required String datasetVersion,
  String? identifier,
}) {
  final name = identifier ?? dartIdentifier(sourceName);
  return '''
// Generated by `dart run geonames_offline:generate` from $sourceName. Do not
// edit. Dataset version: $datasetVersion.
//
// dart format off

import 'dart:convert';
import 'dart:typed_data';

/// The `$sourceName` dataset, ${bytes.length} bytes, decoded from its embedded
/// form. Version: `$datasetVersion`.
Uint8List ${name}DatasetBytes() => base64Decode(_data);

const String _data = '${base64Encode(bytes)}';
''';
}

/// A Dart identifier for a source name: `cities15000` stays as it is,
/// `my-places` becomes `my_places`, and a leading digit gets a `d` prefix.
String dartIdentifier(String sourceName) {
  var id = sourceName.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (id.isEmpty || RegExp(r'^[0-9]').hasMatch(id)) id = 'd$id';
  return id;
}
