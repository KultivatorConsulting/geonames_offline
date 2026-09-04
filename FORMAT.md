# Dataset format

Format version 1. `lib/src/format.dart` is the reference encoder and decoder;
this document is the specification it implements.

All integers are little-endian. A *string* is a 16-bit byte length followed by
that many bytes of UTF-8. A *string index* is a 32-bit position in the string
table; `0xFFFFFFFF` means "no string".

## Layout

| Offset | Size               | Content                                              |
| ------ | ------------------ | ---------------------------------------------------- |
| 0      | 4                  | Magic, the ASCII bytes `GNOF`                        |
| 4      | 1                  | Format version, `1`                                  |
| 5      | 3                  | Reserved, zero                                       |
| 8      | 4                  | `recordCount`                                        |
| 12     | 4                  | `countryCount`                                       |
| 16     | 4                  | `admin1Count`                                        |
| 20     | 4                  | `stringCount`                                        |
| 24     | variable           | Dataset version, a string                            |
|        | variable           | Attribution, a string                                |
|        | variable           | String table: `stringCount` strings                  |
|        | 8 × `countryCount` | Country table                                        |
|        | 8 × `admin1Count`  | Admin1 table                                         |
|        | 20 × `recordCount` | Records                                              |

A country table entry is two string indexes: the ISO 3166-1 alpha-2 code, then
the display name. An admin1 table entry is two string indexes: the GeoNames
`admin1` code, then the display name, which may be "no string" when the export
has no name for that code.

A record is:

| Offset | Type | Field                                                     |
| ------ | ---- | --------------------------------------------------------- |
| 0      | i32  | GeoNames identifier                                       |
| 4      | i32  | Latitude, in units of 10⁻⁷ degrees                        |
| 8      | i32  | Longitude, in units of 10⁻⁷ degrees                       |
| 12     | u32  | Name, a string index                                      |
| 16     | u16  | Country, an index into the country table                  |
| 18     | u16  | Admin1, an index into the admin1 table, or `0xFFFF` = none |

Coordinates as integers make the asset independent of floating-point
formatting and exactly reproduce GeoNames' values, which carry at most five
decimals. Dividing by 10⁷ gives the same `double` as parsing the original
text.

## Order

Everything is ordered, so that identical input gives identical bytes:

- The string table is deduplicated and sorted by UTF-16 code units.
- The country table is sorted by code; the admin1 table by country code, then
  admin1 code.
- Records are in **spatial index order**, described next. The dataset does not
  store a separate index; the record order *is* the index.

## Spatial index order

Records form an implicit k-d tree over their positions as unit vectors on the
sphere. For any range `[lo, hi)` of records, the record at `(lo + hi) >> 1` is
the split node; records in `[lo, m)` are on or below it along the range's
axis and records in `(m, hi)` on or above. The axis cycles through x, y and z
with depth, starting at x for the whole array. Ties on an axis are broken by
ascending GeoNames identifier.

Working in three dimensions rather than latitude and longitude is what makes
the antimeridian and the poles unremarkable: chord distance between unit
vectors is monotonic in great-circle distance, and the pruning planes are
ordinary Euclidean planes. The resolver converts the winning chord to metres
at the end.

The unit vectors are computed with the package's own deterministic sine and
cosine (`lib/src/trig.dart`), not the platform's C library, so that the order
is bit-identical on every machine. The resolver uses the same functions, so
the invariant it relies on holds exactly.

## Dataset version

The generator derives the version string from the content, never from the
clock: the export name, the country filter if any, the latest `modification
date` among the kept rows, and the row count. For example
`cities15000 2026-09-03 (34135 places)` or `cities1000 AU,NZ 2026-08-30 (2140
places)`. It can be overridden on the command line.

## Compatibility

The reader refuses any format version other than the one it implements. A
layout change is a new format version; a new package version can read old
datasets only if it says so.
