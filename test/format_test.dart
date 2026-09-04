// What would have to break: the byte layout, an index table, string interning,
// or the decoder's validation of malformed input.

import 'dart:typed_data';

import 'package:geonames_offline/src/format.dart';
import 'package:test/test.dart';

const _records = [
  PlaceRecord(
    geonameId: 2179537,
    name: 'Wellington',
    latE7: -412866400,
    lonE7: 1747755700,
    countryCode: 'NZ',
    admin1Code: 'G2',
  ),
  PlaceRecord(
    geonameId: 6691831,
    name: 'Vatican City',
    latE7: 419026800,
    lonE7: 124541400,
    countryCode: 'VA',
    admin1Code: null,
  ),
  PlaceRecord(
    geonameId: 90000007,
    name: 'Nowhere',
    latE7: 100000000,
    lonE7: 100000000,
    countryCode: 'NG',
    admin1Code: '00',
  ),
];

const _countries = {'NZ': 'New Zealand', 'VA': 'Vatican City', 'NG': 'Nigeria'};
const _admin1 = {'NZ.G2': 'Wellington'};

Uint8List _encode({List<PlaceRecord> records = _records}) => encodeDataset(
  datasetVersion: 'fixture 2025-06-10 (3 places)',
  attribution: 'attribution text',
  records: records,
  countryNames: _countries,
  admin1Names: _admin1,
);

void main() {
  test('round-trips every field, preserving record order', () {
    final d = decodeDataset(_encode());
    expect(d.length, 3);
    expect(d.datasetVersion, 'fixture 2025-06-10 (3 places)');
    expect(d.attribution, 'attribution text');

    final wellington = d.placeAt(0);
    expect(wellington.geonameId, 2179537);
    expect(wellington.name, 'Wellington');
    expect(wellington.latitude, -41.28664);
    expect(wellington.longitude, 174.77557);
    expect(wellington.countryCode, 'NZ');
    expect(wellington.countryName, 'New Zealand');
    expect(wellington.admin1Code, 'G2');
    expect(wellington.admin1Name, 'Wellington');

    final vatican = d.placeAt(1);
    expect(vatican.geonameId, 6691831);
    expect(vatican.admin1Code, isNull);
    expect(vatican.admin1Name, isNull);
    expect(vatican.countryName, 'Vatican City');

    final nowhere = d.placeAt(2);
    expect(nowhere.admin1Code, '00', reason: 'code is verbatim');
    expect(nowhere.admin1Name, isNull, reason: 'no name in the table');
  });

  test('an empty dataset encodes and decodes', () {
    final d = decodeDataset(_encode(records: const []));
    expect(d.length, 0);
    expect(d.datasetVersion, isNotEmpty);
  });

  test('rejects data that is not a dataset', () {
    final bytes = _encode();
    expect(
      () => decodeDataset(Uint8List.fromList([...'GNOX'.codeUnits, 1, 0, 0])),
      throwsFormatException,
    );
    final wrongVersion = Uint8List.fromList(bytes)..[4] = 2;
    expect(() => decodeDataset(wrongVersion), throwsFormatException);
    expect(
      () => decodeDataset(bytes.sublist(0, bytes.length - 7)),
      throwsFormatException,
      reason: 'truncated',
    );
    expect(
      () => decodeDataset(Uint8List.fromList([...bytes, 0])),
      throwsFormatException,
      reason: 'trailing bytes',
    );
  });

  test('refuses to encode a country it cannot name', () {
    expect(
      () => encodeDataset(
        datasetVersion: 'v',
        attribution: 'a',
        records: _records,
        countryNames: const {'NZ': 'New Zealand'},
        admin1Names: const {},
      ),
      throwsArgumentError,
    );
  });

  test('refuses a string the length prefix cannot hold', () {
    final records = [
      PlaceRecord(
        geonameId: 1,
        name: 'x' * 70000,
        latE7: 0,
        lonE7: 0,
        countryCode: 'NZ',
        admin1Code: null,
      ),
    ];
    expect(() => _encode(records: records), throwsArgumentError);
  });
}
