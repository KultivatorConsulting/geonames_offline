# Plan

Slices are ordered. Slice 1 exists to unblock a downstream consumer and should
land on its own, quickly, before anything else is started.

## Slice 1 — Repository bootstrap and the tagged API surface

The consumer is blocked on the **shape**, not the behaviour, so ship the shape.

- `git init`, licence files, README, `pubspec.yaml`, `analysis_options.yaml`.
- GitHub Actions running `dart analyze` and `dart test` on the Dart VM.
- The `ReverseGeocoder` interface and the `GeoPlace` value type exactly as
  DESIGN.md specifies, with implementation bodies throwing `UnimplementedError`.
- Tag it — `v0.1.0-api` or similar.

**Acceptance:** a consumer can add this repo as a git dependency pinned to that
tag, write their own class implementing `ReverseGeocoder`, and compile against
it. Nothing more.

Do not start slice 2 before this is tagged. The parallelism this project is
relying on comes entirely from this slice landing early.

## Slice 2 — Generator and the prebuilt dataset

- Fetch and parse a GeoNames export (`cities15000`, `cities1000`, plus the
  `admin1CodesASCII` and `countryInfo` tables needed for display names).
- Emit the package's binary format.
- Accept a country filter, so a consumer shipping to one market pays for one.
- Stamp the CC BY attribution into every dataset produced.
- Commit the prebuilt `cities15000` asset.

**Acceptance:** the generator reproduces the committed asset byte-for-byte from a
given GeoNames export. Determinism matters — it is what makes the automated
regeneration in slice 5 reviewable.

## Slice 3 — Resolver and spatial index

- Load the binary asset; build the in-memory index.
- Implement `nearest`, `byId`, `datasetVersion`, `attribution`.
- Great-circle distance in metres.
- Enough tests to prove the happy path; the hard cases are slice 4.

**Acceptance:** the interface from slice 1 is fully implemented and the
`UnimplementedError` bodies are gone.

## Slice 4 — The adversarial corpus

See TESTING.md, which is the specification for this slice. This is the slice
that makes the package's accuracy claim mean something, and it is the one most
likely to be skimped. Do not skimp it.

**Acceptance:** every case named in TESTING.md has a test, each asserting on
`geonameId` rather than on a display name.

## Slice 5 — Automated regeneration

A scheduled workflow that pulls the current GeoNames export, regenerates,
runs the full corpus, and opens a pull request **only if the corpus passes**.

⚠ The gate is the point. An automated data bump without a corpus behind it is an
automated regression with a green tick on it.

**Acceptance:** a deliberately corrupted input produces no pull request.

## Slice 6 — Publication

- README with usage, both licences stated separately, and the note that
  generator-built datasets refresh by re-running the generator rather than by
  upgrading the package.
- Publish to pub.dev.
- Consumer moves from the git dependency to the published version.

---

# Open decisions

These need an answer before the slice that depends on them. Ask rather than
picking silently.

1. **Code licence** — MIT, BSD-3-Clause, or Apache-2.0. MIT is the most common in
   the Dart ecosystem and the least friction for adopters; Apache-2.0 adds an
   explicit patent grant. Needed in slice 1. *(Decided 2026-09-05: MIT.)*
2. **Where the repository lives** — a personal GitHub account or an
   organisation. Needed in slice 1. *(Decided 2026-09-05:
   github.com/KultivatorConsulting/geonames_offline.)*
3. **Binary format specifics** — record layout, string interning for repeated
   country and admin1 names, and whether the spatial index is built at load time
   or serialised into the asset. Load-time construction over ~25k rows is likely
   fast enough to make serialising it a premature optimisation, but measure
   rather than assume. Needed in slice 2. *(Decided 2026-09-05: see FORMAT.md.
   Record order is the index, so nothing is built at load and nothing extra is
   serialised; decoding 34k places takes ~5 ms AOT.)*
4. **Default dataset shipped in the package** — `cities15000` worldwide is the
   assumption. Confirm the resulting package size is acceptable to pub.dev and to
   app binaries before committing the asset. Needed in slice 2. *(Decided
   2026-09-05: confirmed. 34,135 places are 1.11 MB uncompressed, 0.71 MB
   gzipped, against pub.dev's 100 MB archive limit.)*
5. **Regeneration cadence** — GeoNames publishes daily. Monthly is likely
   sufficient, since each release costs every consumer an upgrade decision.
   Needed in slice 5.
