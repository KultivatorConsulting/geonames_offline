# Testing

This package exists to make an accuracy claim. The claim is worth exactly as much
as the fixtures behind it, and no more.

## The question to ask of every test

**What would have to break for this test to fail?**

If the answer is "nothing plausible", the test is decoration — it will stay green
through the bug it appears to guard, and its greenness will be read as evidence.
That is worse than having no test, because a missing test is visible and a test
that cannot fail is not.

The canonical example for this package:

> A test asserting that Wellington's coordinates resolve to `Wellington`
> **passes against a completely broken index** if the fixture dataset contains
> only one Wellington. A stub returning the single row it holds passes too.

Two rules follow, and they apply to every test in this repository:

1. **The fixture must contain the confusable cases.** Several Wellingtons, in
   several countries. A near-miss city just outside the expected answer.
2. **Assert on `geonameId`, never on a display name.** Names are ambiguous by
   nature — that ambiguity is the thing being tested — so an assertion on a name
   cannot distinguish the right answer from a coincidence.

## Fixture strategy

Use a **small, purpose-built dataset committed to the repository**, not the real
`cities15000`, for the behavioural tests. It is deterministic, it is fast, and —
most importantly — it can be *constructed* to contain the adversarial cases,
which a real-world extract only contains by luck.

Keep a handful of smoke tests against the real prebuilt asset to prove the
generator's output loads and resolves sensibly. Those are not where correctness
is established.

## Required cases

| Case | What it proves |
|---|---|
| **Duplicate names across countries** — several Wellingtons | Resolution is by position and identity, not by name. The single most important case. |
| **Rural point, no city nearby** | `nearest` still answers, and `distanceMetres` is large and correct — the package applies no radius policy of its own. |
| **Equidistant between two cities** | The tie-break is deterministic and documented, rather than dependent on insertion order. |
| **Antimeridian** — New Zealand's Chatham Islands sit east of 180° | Longitude wrap-around is handled. A naive planar distance gets this catastrophically wrong, and it is on our own doorstep. |
| **Poles** — points at and adjacent to ±90° latitude | No division-by-zero, no NaN, no infinite distance. |
| **Open ocean** | Returns a distant coastal city rather than null or an error. Correct, and easily mistaken for a bug. |
| **Retired identifier** — `byId` with an id absent from the dataset | Returns `null`, and specifically **not** a nearest-match substitute. This is the case a downstream consumer depends on to detect a dangling stored reference. |
| **Empty dataset** | `nearest` returns `null` rather than throwing. |
| **Invalid coordinates** — out of range, NaN | Documented behaviour, consistently applied. |

## Determinism

The generator's output must be byte-for-byte reproducible from a given GeoNames
export. This is what makes the automated regeneration workflow reviewable: a
diff that shows only the rows that actually changed upstream, rather than noise
from map ordering or timestamps.

A test should assert this directly, by generating twice and comparing.
