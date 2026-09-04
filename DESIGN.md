# Design

## The contract

This is the whole public surface. It ships first, tagged, before any
implementation exists (see PLAN.md slice 1).

```dart
/// A populated place. Returned by both lookups.
class GeoPlace {
  /// ISO 3166-1 alpha-2, e.g. `NZ`.
  final String countryCode;

  /// GeoNames `admin1` code, verbatim. See "Hierarchy is returned verbatim".
  final String? admin1Code;

  /// The GeoNames identifier. Stable enough to store, but see
  /// "Identifiers are not stable across releases".
  final int geonameId;

  /// Display name of the place itself, e.g. `Wellington`.
  final String name;

  /// Display name of the first-order administrative division, if any.
  final String? admin1Name;

  /// Display name of the country, e.g. `New Zealand`.
  final String countryName;

  /// The place's own position in decimal degrees, as GeoNames records it.
  final double latitude;
  final double longitude;
}

/// The answer to a `nearest` query: a place, and how far away it is.
class NearestPlace {
  final GeoPlace place;

  /// Great-circle distance from the query point to [place], in metres.
  final double distanceMetres;
}

abstract class ReverseGeocoder {
  /// The nearest populated place to the point, or `null` if the dataset holds
  /// none at all.
  ///
  /// Applies no radius policy: a point in the middle of an ocean will return
  /// the nearest coastal city, hundreds of kilometres away, and that is
  /// correct behaviour. Callers decide what is too far by reading
  /// [NearestPlace.distanceMetres].
  NearestPlace? nearest(double latitude, double longitude);

  /// Looks up a previously stored identifier.
  ///
  /// Returns `null` when the id is not in this dataset — never a nearest-match
  /// substitute. See "Identifiers are not stable across releases".
  GeoPlace? byId(int geonameId);

  /// Identifies the dataset in use, independently of the package version.
  String get datasetVersion;

  /// The attribution text a consumer must display. See "Two licences".
  String get attribution;
}
```

## Why it is shaped this way

### No radius policy lives in this package

The obvious API would take a `maxDistance` and return `null` beyond it. It is
the wrong shape, because "how far is too far" is a **product** decision that
differs per consumer. An app showing regional news is happy with a city 80km
away; an app finding a nearby pharmacy is not. Baking a threshold in would
force every consumer that disagrees to work around it.

So `nearest` always answers if the dataset holds anything, and always reports
the distance. The caller applies its own policy. This also makes the "no city
near this user, fall back to the province" behaviour a caller concern, which is
where it belongs — the package has no idea what a fallback would mean.

### Distance lives on the result, not on the place

`byId` has no query point, so a distance field on `GeoPlace` would be
meaningless for half the API and would need a sentinel — zero, `NaN` or `null`
— that every `nearest` caller then has to know never applies to them. So
`nearest` answers with a `NearestPlace`: the place, plus the distance from the
query point. `GeoPlace` carries the place's own coordinates instead, which are
meaningful however it was found and let a caller compute any distance it wants
from a stored id.

### Hierarchy is returned verbatim

GeoNames `admin1` is a first-order administrative division, and what that means
varies by country: a state, a region, a province, a prefecture, or something with
no clean English translation. Any attempt to normalise it into a universal
vocabulary would be lossy, opinionated, and wrong somewhere.

The package therefore returns **GeoNames' own values, unmodified**, and both the
code and the field name say so. Consumers that need a friendlier label map it
themselves, with knowledge of their own audience.

### Not-found is `null`, not an exception

Both lookups return nullable rather than throwing. A coordinate with no match
and an id that is not present are **ordinary outcomes**, not errors — and a
nullable return makes the caller handle them at the call site, which an exception
does not.

### ⚠ Identifiers are not stable across releases

GeoNames retires, merges and splits entries between releases. A `geonameId` is
therefore a **reference into data that will be replaced**, and consumers that
persist one will eventually hold a dangling reference.

`byId` must return `null` for an unknown id and **must never substitute a nearest
match**. A silent substitution converts a stale record into a confidently wrong
one, which is materially worse than the error it hides: the consumer has no way
to detect it and no reason to suspect it. Making the dangling case visible is the
package's obligation; deciding what to do about it is the consumer's.

## Storage and indexing

A compact binary asset, loaded and queried through an **in-memory spatial index**
(a k-d tree over the coordinates is sufficient and is what the prior art used).
Distances are great-circle metres on a sphere of radius 6,371,008.8 m, the
IUGG mean Earth radius.

**Not SQLite.** `sqflite` is Flutter-bound, which would break the pure-Dart
constraint outright; `sqlite3` via FFI drags in per-platform native libraries and
makes a package that should be trivially portable into one with a build matrix.
Neither is worth it for a dataset that is a few tens of thousands of rows and
fits comfortably in memory.

### Decided: the record order is the index

FORMAT.md is the specification. The points that were open:

- **Coordinates are 32-bit integers in 10⁻⁷ degrees.** GeoNames publishes at
  most five decimals, so this is lossless, and it keeps floating-point
  formatting out of the asset.
- **Strings are interned** in one sorted table; countries and first-order
  divisions are small tables that records point into.
- **The index is neither built at load time nor serialised separately.** The
  generator writes records in implicit k-d tree order over their unit vectors
  on the sphere, so loading is a straight decode and querying walks the array.
  Working in three dimensions is what makes the antimeridian and the poles
  ordinary cases rather than special ones.
- **Trigonometry is the package's own**, not the C library's, so the order is
  bit-identical on every machine. Reproducibility is measured by generating
  twice and comparing, and it holds byte for byte.

Measured on the 2026-09-03 export: 34,135 places encode to 1.11 MB (0.71 MB
gzipped), generation takes under a second, and decoding takes about 5 ms
ahead-of-time compiled or 25 ms on a cold JIT.

### Decided: the bundled dataset is a Dart constant

A pure-Dart package has no portable way to read a file of its own at runtime:
Flutter needs an asset declaration in the consuming app, a server needs
package-URI resolution, an ahead-of-time compiled executable has neither, and
the web has none of the above. So the generator can also emit the dataset as
a Dart library holding it base64-encoded in a `const String`, and that is how
`cities15000` ships (`lib/src/data/cities15000.dart`, 1.48 MB of source).
`GeonamesReverseGeocoder.cities15000()` decodes it on demand; a consumer that
never calls it gets it tree-shaken away. The raw binary is not shipped as
well, since that would double the package for no reader.

### Decided: invalid coordinates throw, ties go to the lower id

`NaN`, infinities and a latitude beyond ±90 are programming errors and throw
`ArgumentError`; `null` stays reserved for "nothing to find". Any finite
longitude is accepted and wrapped into ±180, because callers holding
longitudes in `[0, 360)` are common and there is exactly one right answer.
Two places exactly equidistant from a query resolve to the lower `geonameId`,
so a result never depends on insertion order.

## Datasets

Two sizes, from the GeoNames exports:

| Dataset | Rows | Notes |
|---|---|---|
| `cities15000` | ~34k | Ships prebuilt. Population 15,000+. |
| `cities1000` | ~130k | Built via the generator. Better rural accuracy, larger asset. |

A **generator** turns a GeoNames export into the package's binary format, and
also accepts a country filter so a consumer shipping to one market pays for one
market.

### Versioning the data separately from the code

GeoNames regenerates its dumps daily, so "the data changed" is a standing
condition rather than an event. A release triggered by three hundred renamed
cities is not a code change, and semver has nothing coherent to say about it.

Hence `datasetVersion`, distinct from the package version, so a consumer can tell
which kind of change they are taking. And note in the README that **a consumer
who built their own dataset does not get data updates by upgrading the package** —
their refresh path is re-running the generator.

## ⚠ Two licences, and they must be stated separately

- **The code** is MIT (see `LICENSE`).
- **The data** is GeoNames, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

These are different licences with different obligations, and a downstream user
who assumes one covers both will get it wrong. State them separately and
explicitly in the README and in `LICENSE`/`LICENSE-DATA`.

CC BY requires attribution to survive into **applications that ship this
package**, not merely into this repository. A line in the README does not
discharge that obligation for an app store binary. Therefore:

- `ReverseGeocoder.attribution` exposes the required text **programmatically**,
  so a consuming app can render it in its own licences screen.
- The generator **stamps the attribution into every dataset it produces**, so a
  custom dataset carries its obligation with it rather than losing it at the
  first copy.

## Non-goals

- **Forward geocoding** (name to coordinates).
- **Street addresses.** The dataset holds populated places and administrative
  divisions. It cannot resolve an address and the package must never imply it
  can — this is why it is not called `reverse_geocoder`.
- **Sub-city granularity.** Suburbs and neighbourhoods are not in these datasets.
- **Timezone from coordinates.** Adjacent and tempting, a different dataset with
  a different licence. If it is ever wanted it is a separate package.
- **Acquiring coordinates.** The caller supplies them. This package never asks
  for a location permission and has no opinion about how the caller got its
  numbers.
