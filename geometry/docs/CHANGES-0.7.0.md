# Changes — v0.7.0 standard constructions

- Eight typed library helpers in `constructions.rkt`, with narrated algorithms
  and numerical postconditions.
- Thirteen application videos and three new library plates in the gallery.
- `Angle`, `Side`, and `Relation` binding types, defining-point/angle accessors,
  `side-of?`, and transferable-compass circles using `#:radius`.
- `expand` auxiliary cleanup and preservation of aliases imported with two prefixes.
- Step-local assertions; false relation values work under Boolean operations;
  assertions validate the chosen realization instead of influencing layout search.
- Dimensionless angular tests corrected; very small valid defining vectors are
  not treated as automatically zero.
- Nondrawable givens no longer appear in the presentation/view state.
- Original helper example promoted to a re-export of the standard library.
- New base-only check runner and native RackUnit integration tests.
- Manifest-driven batch script for light/dark videos; existing process renderer
  and global frame-number merge logic unchanged.
- Updated manual, construction reference, implementation plan, and gallery guide.

Native Animate rasterization was not executed here. See docs/TESTING.md for
validation details and remaining estimated-layout warnings.
