// What would have to break: GeoNames parsing, the country filter, the version
// derivation, the spatial ordering, or determinism of the whole pipeline.

import 'dart:io';
import 'dart:typed_data';

import 'package:geonames_offline/src/format.dart';
import 'package:geonames_offline/src/generator.dart';
import 'package:test/test.dart';

import 'support/spatial_order.dart';

const _dir = 'test/fixtures/geonames';
final _cities = File('$_dir/cities_fixture.txt').readAsStringSync();
final _admin1 = File('$_dir/admin1CodesASCII.txt').readAsStringSync();
final _countryInfo = File('$_dir/countryInfo.txt').readAsStringSync();

({Uint8List bytes, String datasetVersion, int placeCount}) _generate({
  String? cities,
  Set<String>? countries,
  String? datasetVersion,
}) {
  final r = generateDataset(
    citiesTsv: cities ?? _cities,
    admin1CodesTsv: _admin1,
    countryInfoTsv: _countryInfo,
    sourceName: 'cities_fixture',
    countries: countries,
    datasetVersion: datasetVersion,
  );
  return (
    bytes: r.bytes,
    datasetVersion: r.datasetVersion,
    placeCount: r.placeCount,
  );
}

void main() {
  test('generating twice produces identical bytes', () {
    expect(_generate().bytes, orderedEquals(_generate().bytes));
    expect(
      _generate(countries: {'NZ'}).bytes,
      orderedEquals(_generate(countries: {'NZ'}).bytes),
    );
  });

  test('every fixture place survives with its fields intact', () {
    final d = decodeDataset(
      generateDataset(
        citiesTsv: _cities,
        admin1CodesTsv: _admin1,
        countryInfoTsv: _countryInfo,
        sourceName: 'cities_fixture',
      ).bytes,
    );
    expect(d.length, 13);
    final byId = {for (var i = 0; i < d.length; i++) d.geonameIds[i]: i};

    final wellington = d.placeAt(byId[2179537]!);
    expect(wellington.name, 'Wellington');
    expect(wellington.latitude, -41.28664);
    expect(wellington.longitude, 174.77557);
    expect(wellington.countryCode, 'NZ');
    expect(wellington.countryName, 'New Zealand');
    expect(wellington.admin1Code, 'G2');
    expect(wellington.admin1Name, 'Wellington');

    expect(d.placeAt(byId[2657896]!).name, 'Zürich', reason: 'UTF-8 intact');
    expect(d.placeAt(byId[2657896]!).admin1Name, 'Zürich');

    final vatican = d.placeAt(byId[6691831]!);
    expect(vatican.admin1Code, isNull, reason: 'empty admin1 column');
    expect(vatican.admin1Name, isNull);

    final nowhere = d.placeAt(byId[90000007]!);
    expect(nowhere.admin1Code, '00', reason: 'verbatim, even when unnamed');
    expect(nowhere.admin1Name, isNull);

    final waitangi = d.placeAt(byId[90000004]!);
    expect(waitangi.longitude, -176.55973);
    expect(waitangi.admin1Name, 'Chatham Islands');
  });

  test('the dataset version is derived from the content', () {
    expect(_generate().datasetVersion, 'cities_fixture 2025-06-10 (13 places)');
    expect(
      _generate(countries: {'nz'}).datasetVersion,
      'cities_fixture NZ 2025-06-10 (3 places)',
      reason: 'filter is upper-cased and shown; date is the latest kept row',
    );
    expect(
      _generate(countries: {'ZA', 'AR'}).datasetVersion,
      'cities_fixture AR,ZA 2024-11-20 (2 places)',
    );
    expect(
      _generate(countries: {'XX'}).datasetVersion,
      'cities_fixture XX (0 places)',
    );
    expect(_generate(datasetVersion: 'custom').datasetVersion, 'custom');
  });

  test('the country filter keeps exactly the requested countries', () {
    final d = decodeDataset(
      generateDataset(
        citiesTsv: _cities,
        admin1CodesTsv: _admin1,
        countryInfoTsv: _countryInfo,
        sourceName: 'cities_fixture',
        countries: {'nz'},
      ).bytes,
    );
    expect(d.geonameIds, unorderedEquals([2179537, 2193733, 90000004]));
    expect(d.countryCodes, ['NZ']);
    expect(decodeDataset(_generate(countries: {'XX'}).bytes).length, 0);
  });

  test('sections of a place are dropped by default and can be kept', () {
    final byDefault = decodeDataset(_generate().bytes);
    expect(byDefault.geonameIds, isNot(contains(90000010)));
    expect(byDefault.length, 13);

    final kept = decodeDataset(
      generateDataset(
        citiesTsv: _cities,
        admin1CodesTsv: _admin1,
        countryInfoTsv: _countryInfo,
        sourceName: 'cities_fixture',
        excludeFeatureCodes: const {},
      ).bytes,
    );
    expect(kept.geonameIds, contains(90000010));
    expect(kept.length, 14);
    expect(kept.datasetVersion, 'cities_fixture 2025-06-10 (14 places)');
  });

  test('the attribution is stamped into the dataset', () {
    final d = decodeDataset(
      generateDataset(
        citiesTsv: _cities,
        admin1CodesTsv: _admin1,
        countryInfoTsv: _countryInfo,
        sourceName: 'cities_fixture',
      ).bytes,
    );
    expect(d.attribution, geonamesAttribution);
    expect(d.attribution, contains('GeoNames'));
    expect(d.attribution, contains('creativecommons.org/licenses/by/4.0'));
  });

  test('records are stored in valid spatial index order', () {
    final d = decodeDataset(
      generateDataset(
        citiesTsv: _cities,
        admin1CodesTsv: _admin1,
        countryInfoTsv: _countryInfo,
        sourceName: 'cities_fixture',
      ).bytes,
    );
    expect(spatialOrderViolations(d), 0);
    final inputOrder = parseCities(_cities).records.map((r) => r.geonameId);
    expect(inputOrder, hasLength(d.length));
    expect(
      d.geonameIds,
      isNot(orderedEquals(inputOrder)),
      reason: 'input order is not spatial order, so ordering must have run',
    );
  });

  test('malformed input is refused with a line number', () {
    final short = '${_cities}12345\tShort row\n';
    expect(
      () => _generate(cities: short),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('line 15'),
        ),
      ),
    );
    final duplicate = '$_cities${_cities.split('\n').first}\n';
    expect(
      () => _generate(cities: duplicate),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('duplicate geonameid 2179537'),
        ),
      ),
    );
    final badLat = _cities.replaceFirst('-41.28664', '-91.0');
    expect(() => _generate(cities: badLat), throwsFormatException);
  });

  test('a country code missing from countryInfo is an error, not a gap', () {
    final unknown =
        '$_cities\n'
        '${_cities.split('\n').first.replaceFirst('\tNZ\t', '\tZZ\t').replaceFirst('2179537', '90000099')}\n';
    expect(
      () => _generate(cities: unknown),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('"ZZ"'),
        ),
      ),
    );
  });

  group('command line', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('gnof_cli'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('writes a dataset and reports it', () {
      final out = '${temp.path}/nz.gnof';
      final result = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/generate.dart',
        '--cities=$_dir/cities_fixture.txt',
        '--admin1',
        '$_dir/admin1CodesASCII.txt',
        '--country-info',
        '$_dir/countryInfo.txt',
        '--countries',
        'nz',
        '--output',
        out,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('3 places'));
      expect(result.stdout, contains('cities_fixture NZ 2025-06-10'));
      final d = decodeDataset(File(out).readAsBytesSync());
      expect(d.geonameIds, unorderedEquals([2179537, 2193733, 90000004]));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('rejects missing options with the usage exit code', () {
      final result = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/generate.dart',
        '--cities',
        '$_dir/cities_fixture.txt',
      ]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--admin1 is required'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
