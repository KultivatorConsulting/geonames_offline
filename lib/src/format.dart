/// The binary dataset format, version 1. FORMAT.md is the specification; this
/// file is its encoder and decoder.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'reverse_geocoder.dart';

/// The first four bytes of every dataset: `GNOF`.
const List<int> datasetMagic = [0x47, 0x4E, 0x4F, 0x46];

/// The format version this code reads and writes.
const int datasetFormatVersion = 1;

/// Value of a 16-bit index field meaning "none".
const int noIndex16 = 0xFFFF;

/// Value of a 32-bit string index meaning "no string".
const int noString = 0xFFFFFFFF;

/// Bytes per fixed-width place record.
const int recordSize = 20;

/// Bytes of fixed header before the dataset version string.
const int headerSize = 24;

/// One populated place as the generator produces it, before encoding.
final class PlaceRecord {
  /// Creates a record. Coordinates are in 1e-7 degrees.
  const PlaceRecord({
    required this.geonameId,
    required this.name,
    required this.latE7,
    required this.lonE7,
    required this.countryCode,
    required this.admin1Code,
  });

  /// The GeoNames identifier.
  final int geonameId;

  /// Display name of the place.
  final String name;

  /// Latitude in 1e-7 degrees.
  final int latE7;

  /// Longitude in 1e-7 degrees.
  final int lonE7;

  /// ISO 3166-1 alpha-2 country code.
  final String countryCode;

  /// GeoNames `admin1` code, or `null` when the export has none.
  final String? admin1Code;
}

/// Encodes a dataset. [records] must already be in spatial index order; the
/// encoder preserves it. Every country code in [records] must have a name in
/// [countryNames]. [admin1Names] is keyed `CC.CODE` as in
/// `admin1CodesASCII.txt` and may be incomplete: places whose division has no
/// entry get a `null` name.
Uint8List encodeDataset({
  required String datasetVersion,
  required String attribution,
  required List<PlaceRecord> records,
  required Map<String, String> countryNames,
  required Map<String, String> admin1Names,
}) {
  final countryCodes = {for (final r in records) r.countryCode}.toList()
    ..sort();
  if (countryCodes.length >= noIndex16) {
    throw ArgumentError('Too many countries: ${countryCodes.length}');
  }
  for (final code in countryCodes) {
    if (!countryNames.containsKey(code)) {
      throw ArgumentError('No country name for country code "$code"');
    }
  }
  final countryIndex = {
    for (var i = 0; i < countryCodes.length; i++) countryCodes[i]: i,
  };

  final admin1Keys = {
    for (final r in records)
      if (r.admin1Code != null) (r.countryCode, r.admin1Code!),
  }.toList()..sort(_compareAdmin1Keys);
  if (admin1Keys.length >= noIndex16) {
    throw ArgumentError('Too many admin1 divisions: ${admin1Keys.length}');
  }
  final admin1Index = {
    for (var i = 0; i < admin1Keys.length; i++) admin1Keys[i]: i,
  };

  final strings = <String>{};
  for (final r in records) {
    strings.add(r.name);
  }
  for (final code in countryCodes) {
    strings
      ..add(code)
      ..add(countryNames[code]!);
  }
  for (final (country, code) in admin1Keys) {
    strings.add(code);
    final name = admin1Names['$country.$code'];
    if (name != null) strings.add(name);
  }
  final stringList = strings.toList()..sort();
  final stringIndex = {
    for (var i = 0; i < stringList.length; i++) stringList[i]: i,
  };

  final out = _Writer();
  out.bytes(datasetMagic);
  out.u8(datasetFormatVersion);
  out.u8(0);
  out.u16(0);
  out.u32(records.length);
  out.u32(countryCodes.length);
  out.u32(admin1Keys.length);
  out.u32(stringList.length);
  out.string(datasetVersion);
  out.string(attribution);
  for (final s in stringList) {
    out.string(s);
  }
  for (final code in countryCodes) {
    out.u32(stringIndex[code]!);
    out.u32(stringIndex[countryNames[code]!]!);
  }
  for (final (country, code) in admin1Keys) {
    out.u32(stringIndex[code]!);
    final name = admin1Names['$country.$code'];
    out.u32(name == null ? noString : stringIndex[name]!);
  }
  for (final r in records) {
    out.i32(r.geonameId);
    out.i32(r.latE7);
    out.i32(r.lonE7);
    out.u32(stringIndex[r.name]!);
    out.u16(countryIndex[r.countryCode]!);
    final a = r.admin1Code;
    out.u16(a == null ? noIndex16 : admin1Index[(r.countryCode, a)]!);
  }
  return out.takeBytes();
}

int _compareAdmin1Keys((String, String) a, (String, String) b) {
  final c = a.$1.compareTo(b.$1);
  return c != 0 ? c : a.$2.compareTo(b.$2);
}

final class _Writer {
  final _builder = BytesBuilder(copy: false);

  void bytes(List<int> b) => _builder.add(b);

  void u8(int v) => _builder.addByte(v & 0xFF);

  void u16(int v) {
    if (v < 0 || v > 0xFFFF) throw ArgumentError.value(v, 'v', 'not a u16');
    _builder
      ..addByte(v & 0xFF)
      ..addByte((v >> 8) & 0xFF);
  }

  void u32(int v) {
    if (v < 0 || v > 0xFFFFFFFF) {
      throw ArgumentError.value(v, 'v', 'not a u32');
    }
    _builder
      ..addByte(v & 0xFF)
      ..addByte((v >> 8) & 0xFF)
      ..addByte((v >> 16) & 0xFF)
      ..addByte((v >> 24) & 0xFF);
  }

  void i32(int v) {
    if (v < -0x80000000 || v > 0x7FFFFFFF) {
      throw ArgumentError.value(v, 'v', 'not an i32');
    }
    u32(v & 0xFFFFFFFF);
  }

  void string(String s) {
    final encoded = utf8.encode(s);
    if (encoded.length > 0xFFFF) {
      throw ArgumentError('String longer than 65535 bytes: "$s"');
    }
    u16(encoded.length);
    _builder.add(encoded);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

/// A dataset decoded into columnar arrays, indexed by record position.
///
/// Record position is meaningful: the records are stored in spatial index
/// order, so this is the index as well as the data.
final class DecodedDataset {
  DecodedDataset._({
    required this.datasetVersion,
    required this.attribution,
    required this.geonameIds,
    required this.latE7,
    required this.lonE7,
    required this.names,
    required this.countryIndex,
    required this.admin1Index,
    required this.countryCodes,
    required this.countryNames,
    required this.admin1Codes,
    required this.admin1Names,
  });

  /// See [ReverseGeocoder.datasetVersion].
  final String datasetVersion;

  /// See [ReverseGeocoder.attribution].
  final String attribution;

  /// GeoNames identifier per record.
  final Int32List geonameIds;

  /// Latitude per record, in 1e-7 degrees.
  final Int32List latE7;

  /// Longitude per record, in 1e-7 degrees.
  final Int32List lonE7;

  /// Display name per record.
  final List<String> names;

  /// Index into [countryCodes] and [countryNames] per record.
  final Uint16List countryIndex;

  /// Index into [admin1Codes] and [admin1Names] per record, or [noIndex16].
  final Uint16List admin1Index;

  /// Country table: ISO 3166-1 alpha-2 codes.
  final List<String> countryCodes;

  /// Country table: display names, parallel to [countryCodes].
  final List<String> countryNames;

  /// Admin1 table: GeoNames codes.
  final List<String> admin1Codes;

  /// Admin1 table: display names, parallel to [admin1Codes]; `null` when the
  /// export had no name for the code.
  final List<String?> admin1Names;

  /// Number of records.
  int get length => geonameIds.length;

  /// The record at position [i] as the public value type.
  GeoPlace placeAt(int i) {
    final a = admin1Index[i];
    final c = countryIndex[i];
    return GeoPlace(
      countryCode: countryCodes[c],
      admin1Code: a == noIndex16 ? null : admin1Codes[a],
      geonameId: geonameIds[i],
      name: names[i],
      admin1Name: a == noIndex16 ? null : admin1Names[a],
      countryName: countryNames[c],
      latitude: latE7[i] / 1e7,
      longitude: lonE7[i] / 1e7,
    );
  }
}

/// Decodes a dataset produced by [encodeDataset], throwing [FormatException]
/// if [bytes] is not one.
DecodedDataset decodeDataset(Uint8List bytes) {
  try {
    return _decode(bytes);
  } on RangeError {
    throw const FormatException('Dataset is truncated');
  }
}

DecodedDataset _decode(Uint8List bytes) {
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  var offset = 0;

  int u8() => data.getUint8(offset++);
  int u16() {
    final v = data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int u32() {
    final v = data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int i32() {
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  String string() {
    final length = u16();
    final s = const Utf8Decoder().convert(bytes, offset, offset + length);
    offset += length;
    return s;
  }

  for (final expected in datasetMagic) {
    if (u8() != expected) {
      throw const FormatException('Not a geonames_offline dataset');
    }
  }
  final version = u8();
  if (version != datasetFormatVersion) {
    throw FormatException(
      'Unsupported dataset format version $version '
      '(this package reads version $datasetFormatVersion)',
    );
  }
  u8();
  u16();
  final recordCount = u32();
  final countryCount = u32();
  final admin1Count = u32();
  final stringCount = u32();
  final datasetVersion = string();
  final attribution = string();

  final strings = List<String>.generate(stringCount, (_) => string());
  String stringAt(int i) {
    if (i >= strings.length) {
      throw FormatException('String index $i out of range');
    }
    return strings[i];
  }

  final countryCodes = List<String>.filled(countryCount, '');
  final countryNames = List<String>.filled(countryCount, '');
  for (var i = 0; i < countryCount; i++) {
    countryCodes[i] = stringAt(u32());
    countryNames[i] = stringAt(u32());
  }
  final admin1Codes = List<String>.filled(admin1Count, '');
  final admin1Names = List<String?>.filled(admin1Count, null);
  for (var i = 0; i < admin1Count; i++) {
    admin1Codes[i] = stringAt(u32());
    final n = u32();
    admin1Names[i] = n == noString ? null : stringAt(n);
  }

  final geonameIds = Int32List(recordCount);
  final latE7 = Int32List(recordCount);
  final lonE7 = Int32List(recordCount);
  final names = List<String>.filled(recordCount, '');
  final countryIndex = Uint16List(recordCount);
  final admin1Index = Uint16List(recordCount);
  for (var i = 0; i < recordCount; i++) {
    geonameIds[i] = i32();
    latE7[i] = i32();
    lonE7[i] = i32();
    names[i] = stringAt(u32());
    final c = u16();
    if (c >= countryCount) {
      throw FormatException('Country index $c out of range');
    }
    countryIndex[i] = c;
    final a = u16();
    if (a != noIndex16 && a >= admin1Count) {
      throw FormatException('Admin1 index $a out of range');
    }
    admin1Index[i] = a;
  }
  if (offset != bytes.length) {
    throw FormatException(
      'Dataset has ${bytes.length - offset} trailing bytes',
    );
  }

  return DecodedDataset._(
    datasetVersion: datasetVersion,
    attribution: attribution,
    geonameIds: geonameIds,
    latE7: latE7,
    lonE7: lonE7,
    names: names,
    countryIndex: countryIndex,
    admin1Index: admin1Index,
    countryCodes: countryCodes,
    countryNames: countryNames,
    admin1Codes: admin1Codes,
    admin1Names: admin1Names,
  );
}
