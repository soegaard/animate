# Geometry in the shared slide worker pool

Version 0.4.0 · 16 September 2026

**Validated with Racket 9.3.0.2.** The complete 105-case suite passed, including
geometry codec round trips, parent-only preparation accounting, a real two-worker
geometry gallery MP4, and mixed math/geometry subprocess coverage. This change
removes the gallery's automatic one-worker geometry fallback; it does not claim
that ten workers always produce a tenfold speedup.

## The plan

| Stage | Implementation | Acceptance check |
|---|---|---|
| Separate preparation from sampling | Extract the existing geometry annotation/style/provenance preparation into one immutable render record. Preserve the existing drawing algorithm. | Native geometry regression suite; exact prepared-data round trip. |
| Define the transferable representation | A closed, versioned, data-only codec for renderer-consumed geometry, not closures or whole rendered frames. | Primitive/marker/label/color coverage, exact rational duration, invalid input rejection. |
| Integrate parent and worker ownership | Stage one verified geometry artifact per unique preparation; reconstruct the sampler in workers. Retain source fingerprints and original cue times. | Preparation observers show one realization and one layout pass, independent of worker count. |
| Honor project worker policy | Use `make-storyboard-source` for geometry gallery entries, just as for math. Keep explicit `--in-process`. | Actual executor mode and worker-start counts in the console and manifest. |
| Exercise production paths | Test ordinary geometry, semantic checkpoints, portrait/dark output, mixed math/geometry and gallery MP4 output. | PNG equality for local/two/ten workers; a real gallery MP4; normal combined visual probes. |

## Authoring and rendering

No changes to slide declarations are necessary. Both `geometry-content` and
`content-state` around it use the new preparation path. A geometry snapshot nested
inside `semantic-group` remains portable, including a group containing math too.

From the checkout root, render the two semantic geometry examples with:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" slides/run-gallery.rkt \
  --entry semantic-geometry \
  --entry semantic-math-geometry \
  --videos --workers 10 --dark \
  slides-output/geometry-workers-v040-dark

open slides-output/geometry-workers-v040-dark/index.html
```

Use a fresh output directory. The sibling ZIP contains the gallery's media,
posters, samples, source descriptions and manifest, not temporary frame data.

Normal video entries now report the requested capacity before rendering, then
report the actual executor outcome, for example:

```text
semantic-geometry: shared-project video (requested capacity 10).
semantic-geometry: subprocess; started 10 worker(s).
semantic-geometry: ... previews, MP4 complete
```

The validation suite exercised this route with two workers and completed the
`semantic-geometry` MP4. Actual starts can be lower for a small target or a
reuse-only target. `--workers` is a capacity, not a demand to create idle
processes. The current gallery uses cache policy `off`; it does not claim
cross-run frame reuse. Its working frame paths are isolated under
`<gallery>/_work/cache/` to avoid light/dark runs sharing temporary frame files.

Manifest entry fields `mode`, `requested-workers`, `workers-started` and
`workers-completing` distinguish policy from observed execution. Without videos,
`mode` is `static previews` and no frame workers are started. Those previews are
still prepared/rendered in the parent, not distributed across the video pool.

`--in-process` is an explicit local override and retains the gallery's one-worker
local route. Geometry alone no longer selects it automatically.

## Parent preparation

For program content, the parent performs construction realization once per
unique content/preparation context. For ready timeline content, it retains the
supplied realization and timing. Then `prepare-geometry-render!` freezes:

- the exact view, preparation pixel width, drawable order and realized values;
- normal, secondary and highlighted style endpoints and reveal/compass provenance;
- measured label text and positions, marker placements/counts and caption geometry;
- the original presentation events, initial/final states, narration cue spans,
  and total duration.

The returned record contains no original executable construction expression and
no native Visual/Pict closure. Its stripped playback timeline contains only what
`sample-geometry-timeline` reads; it is private renderer data, not a replacement
for a complete public geometry timeline.

The existing geometry drawing code consumes this preparation. Circles remain
native curves, markers retain their geometry, labels retain their fixed placement,
and palette/role references remain semantic color specifications. This is not a
recorded movie or a sampled list of raster frames.

A preparation session shares repeated geometry across semantic checkpoints. In
the gallery, the session spans preview preparation and subsequent project
preparation for an entry. An independent explicit preparation request starts a
new session; there is no global mutable geometry cache.

## Portable data and integrity

`geometry/private/render-preparation-codec.rkt` encodes a closed set of geometry
record tags and ordinary immutable data. It covers points, lines, segments, rays,
circles, angle specifications, all existing marker families, semantic labels,
compass source points, styles, and presentation events. Numbers are not converted
to JSON floats: an exact duration such as `67/10` stays exact. Native color
specifications use Animate's existing color datum codec.

Decoding does not use `eval`, arbitrary deserialization hooks, or module paths
from the data. Unknown tags, executable values, cycles, duplicate identities,
invalid view/timing data and unsupported record extensions are rejected. The
codec bounds recursive decoding work and requires the same Racket version.
The geometry artifact reader reads at most 64 MiB plus one sentinel byte, verifies
the digest of that exact byte snapshot, and reads one data-only datum. This is an
internal, parent-generated preparation protocol, not a general file import API
for arbitrary untrusted documents.

The slide codec stages artifacts under the project-declared asset root in
`.animate-slide-preparation-v1/`, with role `slide-prepared-geometry`. Each unique
prepared geometry object is written once and referenced by its snapshots.
Missing or changed artifacts fail integrity checks. The existing project input
manifest additionally verifies the source/adapter files and assets before frame
execution. Geometry's lazily loaded native adapter dependencies are included
explicitly rather than silently omitted from that manifest.

The outer slide preparation schema is now `animate-slides-preparation-v4`.
The internal geometry record schema is `animate-geometry-render-preparation-v1`.
Old slide payloads are rejected: prepare again rather than mixing schemas.
No manual deletion of old content-addressed artifacts is needed to use the new
schema. Normal bytecode recompilation is needed after updating source.

## Worker reconstruction

Each worker verifies the geometry source fingerprint and decodes the shared
artifact. Repeated references reuse the decoded immutable record within that
worker. `prepared-geometry->visual-sampler` constructs its local native sampler
without running realization, annotation placement, or style/provenance searches.

The original cue map and duration are restored alongside the sampler. Ordinary
`play-content` and semantic bridge replay therefore keep their existing clock
semantics, including exact checkpoint boundaries and arbitrary seek order.
The normal slide and math codecs remain responsible for the other content in a
mixed scene. Geometry does not create a second executor or global time system.

Workers still perform native Visual construction, curve evaluation, drawing,
font rendering and PNG output. Skipping preparation does not mean frame rendering
is free. FFmpeg encoding and static gallery previews are separate stages.

## Source contract and limits

Source modules must remain safe to load in workers: export immutable declarations
and place realization/render effects behind explicit preparation. Prefer
`(geometry-content program)` in a restartable source. A ready timeline is accepted,
but user code that explicitly calls `construction->timeline` at module top level
will still run when that user module is loaded. The adapter cannot prevent those
user-authored effects while importing its source binding.

Font binaries are not serialized. Parent and workers need compatible package
sources, the same Racket version and installed fonts. Here all workers are local
Racket subprocesses; distributed rendering on other machines is not introduced.
Opaque custom renderer values without a supported codec remain unsupported and
are not silently converted to screenshots or switched to one worker.

This update adds a reusable preparation boundary to `geometry/animate.rkt` and
uses it from `animate/slides`. It does **not** migrate the independent
`geometry/examples/private/library-example.rkt` source builder to the new codec;
that standalone example runner retains its existing behavior. The problem fixed
here is geometry embedded in module-backed slide projects and galleries.

## APIs for adapter authors

`animate/geometry/animate` additionally exports:

```racket
(prepare-geometry-render! timeline
                          #:width 1280 #:captions? #t #:labels (hash))
(prepared-geometry-render? value)
(prepared-geometry-render-pixels prepared)
(prepared-geometry-render-duration prepared)
(prepared-geometry->visual-sampler prepared
                                  #:id '$geometry-prepared
                                  #:background theme-background)
```

The last operation returns a sampler accepting a local time or a corresponding
`geometry-frame` snapshot. Existing `geometry-timeline->scene`,
`geometry-timeline->visual` and `geometry-timeline->visual-sampler` keep their
signatures, using the same prepared-data boundary internally. Geometry's pure
`core.rkt` remains independent of Animate rendering.

The private geometry codec offers `prepared-geometry-render->datum`,
`datum->prepared-geometry-render`, and a pure `geometry-source-fingerprint`.
The fingerprint ignores source-location metadata, but detects semantic changes
to the program or supplied timeline. The project manifest independently checks
file digests; a fingerprint is not a replacement for file integrity.

## Acceptance checks

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make -l animate/geometry/animate \
  -l animate/slides -l animate/slides/pict -l animate/slides/scene \
  -l animate/slides/render -l animate/slides/math -l animate/slides/geometry \
  -l animate/slides/project -l animate/slides/gallery slides/run-gallery.rkt &&
"$RACKET" slides/run-tests.rkt --math --geometry --media --project

# The native geometry adapter was refactored, so run its existing regression suite too.
"$RACKET" geometry/run-tests.rkt
```

`--geometry` adds the geometry codec suite. `--geometry --project` adds the real
worker suite, including its small FFmpeg gallery test. Adding `--math` also runs
the mixed-domain ten-worker comparison. The full selection contains 105 supplied
named cases across sixteen suite files; the worker file exports an additional
mixed-domain test suite selected by these flags.

The worker tests compare published PNGs with local, two-process and ten-process
execution. They check actual worker starts, not merely `#:workers` in the request.
A preparation event log inherited by children must contain exactly one realization
and one annotation preparation per unique geometry context, not one per worker.
Unit tests cover reverse sampling, primitive/marker/label/color round trips,
ready timelines, shared snapshot artifacts, and changed or missing input data.

All visual probes remain in the existing combined runner:

```sh
"$RACKET" slides/run-probes.rkt \
  --repeat 2 --gallery --math --geometry \
  slides-output/layout-review-v040
```

The static/native probes inspect composition and repeatability; the worker tests
and gallery manifest supply the separate subprocess evidence. Passing encoding
alone does not establish that a rendered composition looks good.
