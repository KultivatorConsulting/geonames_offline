## Unreleased

- The generator, `dart run geonames_offline:generate`, which turns a GeoNames
  export into a dataset deterministically, with an optional country filter,
  a content-derived dataset version and the CC BY attribution stamped in.
- The binary dataset format, specified in FORMAT.md. Records are stored in
  spatial index order, so there is no index to build at load time.
- The prebuilt `cities15000` dataset at `lib/data/cities15000.gnof`.

## 0.1.0-api

API surface only: the `ReverseGeocoder` interface and its value types,
`GeoPlace` and `NearestPlace`, tagged so that a downstream consumer can compile
against the contract and stub it before an implementation exists. No resolver,
no dataset and no generator yet.
