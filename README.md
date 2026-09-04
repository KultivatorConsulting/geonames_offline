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

## Status

**API surface only.** Tag `v0.1.0-api` ships the `ReverseGeocoder` interface
and its value types, `GeoPlace` and `NearestPlace`, so that a consumer can
compile against the contract, and stub it, while the implementation is built.
There is no resolver, no dataset and no generator yet, and nothing to
instantiate.

## The contract

```dart
import 'package:geonames_offline/geonames_offline.dart';

void describe(ReverseGeocoder geocoder, double latitude, double longitude) {
  final nearest = geocoder.nearest(latitude, longitude);
  if (nearest == null) return; // the dataset holds nothing at all

  // No radius policy is applied for you: decide what is too far yourself.
  if (nearest.distanceMetres > 80000) return;

  final place = nearest.place;
  print('${place.name}, ${place.admin1Name}, ${place.countryName}');
  print(geocoder.attribution); // CC BY 4.0: show this to your users
}
```

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
  id that is not present are ordinary outcomes.
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
from git, pinned to the tag:

```yaml
dependencies:
  geonames_offline:
    git:
      url: https://github.com/KultivatorConsulting/geonames_offline.git
      ref: v0.1.0-api
```

## Datasets

Two sizes are planned, both from the GeoNames exports:

| Dataset        | Rows  | Notes                                                        |
| -------------- | ----- | ------------------------------------------------------------ |
| `cities15000`  | ~25k  | Will ship prebuilt with the package. Population 15,000+.     |
| `cities1000`   | ~130k | Built with the generator. Better rural accuracy, larger.     |

The generator will also accept a country filter, so a consumer shipping to one
market pays for one market.

## Non-goals

- Forward geocoding (name to coordinates).
- Street addresses. The datasets hold populated places and administrative
  divisions; the package cannot resolve an address and will never imply that
  it can.
- Sub-city granularity. Suburbs and neighbourhoods are not in these datasets.
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
