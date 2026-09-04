## 0.1.0

The first working release.

- `GeonamesReverseGeocoder`, the resolver: `nearest` through an implicit k-d
  tree over unit vectors on the sphere, `byId`, `datasetVersion` and
  `attribution`. Invalid coordinates throw `ArgumentError`; any longitude is
  wrapped into ±180; exact ties resolve to the lower `geonameId`.
- `GeonamesReverseGeocoder.cities15000()`, the bundled dataset, embedded as a
  Dart constant so it loads anywhere Dart runs with no asset pipeline.
- The adversarial corpus from TESTING.md: duplicate names across countries,
  rural points, exact ties, the antimeridian, the poles, open ocean, retired
  identifiers, the empty dataset and invalid coordinates, all asserting on
  `geonameId` against a purpose-built fixture.
- Monthly automated regeneration of the bundled dataset, which opens a pull
  request only when the full suite passes against the new data.
- The generator, `dart run geonames_offline:generate`, which turns a GeoNames
  export into a dataset deterministically, with an optional country filter,
  a content-derived dataset version and the CC BY attribution stamped in.
  Rows GeoNames codes as a section of a place (`PPLX`), or as historical,
  abandoned or destroyed, are excluded by default (`--exclude-feature-codes`).
- The binary dataset format, specified in FORMAT.md. Records are stored in
  spatial index order, so there is no index to build at load time.
- The prebuilt `cities15000` dataset at `lib/data/cities15000.gnof`.

## 0.1.0-api

API surface only: the `ReverseGeocoder` interface and its value types,
`GeoPlace` and `NearestPlace`, tagged so that a downstream consumer can compile
against the contract and stub it before an implementation exists. No resolver,
no dataset and no generator yet.
