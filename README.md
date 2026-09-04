# geonames_offline

Offline reverse geocoding for Dart: coordinates in, nearest populated place
out, resolved against an embedded [GeoNames](https://www.geonames.org/)
dataset. No network at resolution time, no platform geocoder, and no Flutter
dependency, so it runs anywhere Dart does, including servers and plain
`dart test` on the VM.

It exists because some applications must never let a user's coordinates leave
the device. Everything about its shape follows from that constraint: if a
change would need a network call to resolve a coordinate, it is wrong for this
package no matter how much more accurate it would be.

## Usage

```dart
import 'package:geonames_offline/geonames_offline.dart';

void main() {
  final geocoder = GeonamesReverseGeocoder.cities15000();

  final nearest = geocoder.nearest(-41.29, 174.78);
  if (nearest == null) return; // only an empty dataset answers null

  // No radius policy is applied for you: decide what is too far yourself.
  if (nearest.distanceMetres > 80000) return;

  final place = nearest.place;
  print('${place.name}, ${place.admin1Name}, ${place.countryName}');
  // Wellington, Wellington Region, New Zealand
  print('${nearest.distanceMetres.round()} m away'); // 490 m away
  print(geocoder.attribution); // CC BY 4.0: show this to your users
}
```

`GeonamesReverseGeocoder.cities15000()` loads the bundled dataset, which is
embedded in the package as a Dart constant: no asset declaration, no file I/O,
and it works the same on Flutter, the Dart VM, ahead-of-time compiled
executables and the web. Loading takes about ten milliseconds ahead-of-time
compiled and holds around 34,000 places in memory; do it once and share the
instance. `GeonamesReverseGeocoder.fromBytes` loads a dataset you built
yourself, from wherever you keep it.

`ReverseGeocoder` is the interface. Code against it, and substitute a stub in
tests.

## The contract

The design choices behind the shape, and the reasoning for each, are in
[DESIGN.md](DESIGN.md). In brief:

- **No radius policy.** `nearest` always answers if the dataset holds anything,
  and always reports the distance. How far is too far is a product decision
  that differs per consumer, so the caller makes it.
- **Distance is on the result, not the place.** Only a query has a point to
  measure from, so `nearest` answers with a `NearestPlace` that pairs the
  `GeoPlace` with the distance. A `GeoPlace` carries its own coordinates,
  which are meaningful however it was found.
- **Hierarchy is returned verbatim.** `admin1Code` and `admin1Name` are
  GeoNames' own values. What a first-order division is varies by country, and
  no universal vocabulary would be right everywhere.
- **Not-found is `null`, not an exception.** A coordinate with no match and an
  id that is not present are ordinary outcomes. A coordinate that is not a
  coordinate, `NaN` or a latitude beyond ±90, is a programming error and
  throws `ArgumentError`. Any longitude is accepted and wrapped into ±180.
- **Ties are deterministic.** Two places exactly equidistant from the query
  resolve to the lower `geonameId`, so the answer is a pure function of the
  query and the dataset.
- **Distances are great-circle metres** on a sphere of radius 6,371,008.8 m.
- **`byId` never substitutes a nearest match.** GeoNames retires, merges and
  splits entries between releases, so a stored `geonameId` will eventually
  dangle. `byId` returns `null` for it, so that the consumer can detect the
  case rather than be handed a confidently wrong answer.
- **The dataset is versioned separately from the code.** `datasetVersion`
  tells you which kind of change you are taking. A consumer that builds its
  own dataset with the generator does not get data updates by upgrading the
  package; its refresh path is re-running the generator.

## Installing

Until the package is published to pub.dev, depend on this repository directly
from git, pinned to a tag:

```yaml
dependencies:
  geonames_offline:
    git:
      url: https://github.com/KultivatorConsulting/geonames_offline.git
      ref: v0.1.0
```

Tag `v0.1.0-api` is the interface alone, with no implementation, for
consumers who need to compile against the contract before adopting the data.

## Datasets

Two sizes, both from the GeoNames exports:

| Dataset        | Rows  | Size    | Notes                                                    |
| -------------- | ----- | ------- | -------------------------------------------------------- |
| `cities15000`  | ~32k  | 1.0 MB  | Bundled; `GeonamesReverseGeocoder.cities15000()`. Population 15,000+. |
| `cities1000`   | ~150k | ~5 MB   | Build it with the generator. Better rural accuracy.      |

The generator also accepts a country filter, so a consumer shipping to one
market pays for one market: New Zealand and Australia together come to 13 KB.

### Building your own dataset

```sh
tool/fetch_geonames.sh cities1000        # downloads to build/geonames/
dart run geonames_offline:generate \
  --cities build/geonames/cities1000.txt \
  --admin1 build/geonames/admin1CodesASCII.txt \
  --country-info build/geonames/countryInfo.txt \
  --countries NZ,AU \
  --output assets/places.gnof \
  --dart lib/places_dataset.dart
```

`--output` writes the binary dataset, to load with
`GeonamesReverseGeocoder.fromBytes` from an asset or a file. `--dart` writes
a Dart library that embeds the same bytes and exposes them as a function, the
way the bundled dataset ships, so that nothing has to be loaded at all. Use
either or both.

The output is deterministic: the same export produces the same bytes, on any
machine. Its `datasetVersion` is derived from the export's content, for
example `cities1000 AU,NZ 2026-08-30 (2140 places)`, and the CC BY attribution
is stamped into it. [FORMAT.md](FORMAT.md) specifies the layout.

A dataset you built yourself does not change when you upgrade the package.
Its refresh path is running the generator again.

### How the bundled dataset stays current

A monthly workflow pulls the current GeoNames export, regenerates the bundled
dataset, runs the full test suite against it, and opens a pull request only
if everything passed and the data changed. A release that merges one changes
`datasetVersion` and nothing else, so you can tell a data update from a code
change before taking it.

## Non-goals

- Forward geocoding (name to coordinates).
- Street addresses. The datasets hold populated places and administrative
  divisions; the package cannot resolve an address and will never imply that
  it can.
- Sub-city granularity. GeoNames' exports do include populous sections of
  cities (boroughs, arrondissements, districts; feature code `PPLX`), and the
  generator drops them by default, along with historical, abandoned and
  destroyed places, so that the answer is the place rather than a part of it.
  `--exclude-feature-codes` changes that for a dataset you build.
- Timezone from coordinates. A different dataset with a different licence.
- Acquiring coordinates. The caller supplies them; this package never asks for
  a location permission.

## Licences

There are two, and they are different.

- **The code** is MIT. See [LICENSE](LICENSE).
- **The data** is GeoNames, under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). See
  [LICENSE-DATA](LICENSE-DATA).

CC BY 4.0 requires attribution to reach the users of an application that ships
this package, not merely the readers of this repository. The package exposes
the required text through `ReverseGeocoder.attribution` so that you can render
it in your own licences screen, and the generator stamps it into every dataset
it produces.

## Contributing

Issues and pull requests are welcome on GitHub. Read
[CLAUDE.md](CLAUDE.md) for the constraints that are not negotiable,
[DESIGN.md](DESIGN.md) for the reasoning behind the contract, and
[TESTING.md](TESTING.md) before writing a test: this package's whole value is
an accuracy claim, and an accuracy claim is worth exactly what its fixtures
are worth.
