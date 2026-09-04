// Smoke tests against the prebuilt asset. Correctness is established against
// the purpose-built fixture, not here (see TESTING.md); these prove that the
// shipped bytes decode, look like the export they were built from, and hold
// the index invariant at full scale.

import 'package:geonames_offline/src/data/cities15000.dart';
import 'package:geonames_offline/src/format.dart';
import 'package:test/test.dart';

import 'support/spatial_order.dart';

void main() {
  late final DecodedDataset d;
  setUpAll(() {
    d = decodeDataset(cities15000DatasetBytes());
  });

  test('decodes to the expected shape and carries its obligations', () {
    expect(d.length, inInclusiveRange(25000, 60000));
    expect(d.datasetVersion, startsWith('cities15000 '));
    expect(d.datasetVersion, endsWith('(${d.length} places)'));
    expect(d.attribution, contains('GeoNames'));
    expect(d.attribution, contains('creativecommons.org/licenses/by/4.0'));
    expect(d.countryCodes.length, inInclusiveRange(150, 260));
    expect(d.countryNames, isNot(contains('')));
  });

  test('holds Wellington where GeoNames puts it', () {
    final i = d.geonameIds.indexOf(2179537);
    expect(i, isNonNegative, reason: 'Wellington, NZ is in cities15000');
    final p = d.placeAt(i);
    expect(p.name, 'Wellington');
    expect(p.countryCode, 'NZ');
    expect(p.countryName, 'New Zealand');
    expect(p.admin1Code, isNotNull);
    expect(p.admin1Name, isNotNull);
    expect(p.latitude, closeTo(-41.2866, 0.01));
    expect(p.longitude, closeTo(174.7756, 0.01));
  });

  test('is stored in valid spatial index order at full scale', () {
    expect(spatialOrderViolations(d), 0);
  });
}
