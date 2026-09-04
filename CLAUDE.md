# geonames_offline — working instructions

## What this is

A pure-Dart, offline reverse geocoder. Coordinates in, nearest populated place
out, resolved against an embedded [GeoNames](https://www.geonames.org/) dataset.
No network at resolution time, no platform geocoder, no Flutter.

It originated as a component of [Rallee Me](https://rallee.me), whose requirement
is that **a user's coordinates never leave their device**. That constraint is
where everything else in this design comes from. If a change would require a
network call to resolve a coordinate, it is wrong for this package — no matter
how much more accurate it would be.

## Hard constraints

1. **Pure Dart. No Flutter dependency, ever.** This rules out `sqflite`,
   `path_provider`, and everything from the Flutter SDK. Tests must run on the
   Dart VM with `dart test`. This is what makes the package usable server-side
   and cheap to test, and it is not negotiable for convenience.
2. **No network at resolution time.** The generator may fetch from GeoNames.
   Resolving a coordinate must never touch the network, directly or transitively.
3. **This repository is public from its first commit.** No internal URLs, no
   private CI configuration, no credentials, no private hostnames, no employer
   infrastructure details. Assume every commit is read by strangers, because it
   is.
4. **The API surface ships first.** The interface and value types are committed
   and tagged *before* any implementation, because a downstream consumer is
   blocked on the shape rather than the behaviour and will shim against that tag.
   See PLAN.md slice 1.
5. **No consumer-specific concepts.** This package answers "what place is at this
   coordinate". It knows nothing about the app using it — no user settings, no
   preferences, no policy about how far is too far. See DESIGN.md.

## Testing discipline

**Read TESTING.md before writing a test.** This package's whole value is an
accuracy claim, and an accuracy claim is worth exactly as much as the fixtures
behind it.

The specific failure to avoid: a test that passes for a reason unrelated to the
thing it names. Asserting that "Wellington resolves to Wellington" passes against
a completely broken index if the fixture contains only one Wellington. Before
committing any test, ask what would have to break for it to fail — and if the
answer is "nothing plausible", the test is decoration.

## Conventions

- Current stable Dart, null-safe throughout.
- Every public API element carries a `///` doc comment. pub.dev scores
  documentation coverage and it is the difference between a package people adopt
  and one they skim past.
- Formatting: `dart format` is the ecosystem norm and pub.dev scores compliance.
  Apply it to files you are already changing; do not reformat the repository
  wholesale inside a change that is about something else. CI checks formatting
  with the **latest stable** Dart, as pub.dev does, and its output changes
  between releases; a Flutter-bundled SDK usually lags, so format with a
  standalone SDK that matches CI when they differ.
- This repository's tracker is GitHub issues. Do not reference any other tracker
  in committed files.

## Before you start

Read **DESIGN.md** for the contract and why it is shaped the way it is, then
**PLAN.md** for the ordered slices and the decisions still open, then
**TESTING.md**.

If something in those documents looks wrong, say so before building around it.
They were written before any code existed and are not sacred — but they encode
reasoning that is easy to lose and expensive to rediscover.
