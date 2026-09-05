#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate/project
                     animate/render))

@section{Project Planning}

@racketmodname[animate/project] has one immutable declaration for source
loading, preview settings, raster rendering, output, encoding, assets, and
caches. @racket[plan-project] is pure; @racket[prepare-project!] may load a
declared source and inspect tools but does not create frames or media.  For an
MP4 project, preparation also records the selected FFmpeg release banner in
its tool identity, so a tool upgrade cannot silently reuse an incompatible
encoded segment.

@racketblock[
(require animate/project)

(define plan
  (plan-project derivative-project
                #:target (project-target-section 'explanation)))
(project-plan->datum plan)]

The effectful operations in @racketmodname[animate/render] reduce section,
block, range, and single-frame requests to @racket[execute-prepared-project!].
See @filepath{examples/project-planning.rkt} and use
@tt{raco animate plan examples/project-planning.rkt sample-project} to inspect
the exact path plan before output is created.

The all-project target uses the declared output name. Narrower targets receive
a deterministic suffix, such as @tt{derivative-explanation.mp4} for a named
section or @tt{derivative-frame-90.mp4} for one frame. Section and block names
are encoded as a single portable path component, so authored names never create
accidental output subdirectories.

@tt{raco animate check PROJECT.rkt BINDING} performs the corresponding
non-rendering environment check.  It loads and validates the declared source,
checks required tools and assets, and verifies that the output and cache roots
are directories that can be used (or created from a writable ancestor).  The
command deliberately creates no directories and writes no probe files; a
changed file system can still cause a later render to report an ordinary I/O
error.

For an MP4 target, the check also asks the selected FFmpeg whether it provides
the declared video encoder and pixel format.  This catches a misspelled codec
or a platform-specific encoder omission before the project invests time in
rasterizing frames.

A @racket['png-sequence] output writes a completed directory of numbered PNGs
at the planned primary output path; cache frames remain internal.  Set
@racket[output-spec]'s @racket[#:write-frame-sequence?] option for the same
explicit PNG export beside an MP4.  Existing exports require
@racket['replace] as the overwrite policy.  Each sequence is copied to a
private sibling and installed only once it is complete.

For an all-target authored timeline, @racket[#:write-sections? #t] additionally
renders every named section as its own normal project target. Those outputs use
the target suffixes above, preserve section-local media semantics, and appear
under the @racket['sections] entry of the execution report. Requesting that
option for a plain Scene is an error: sections are authoring metadata, not an
implicit division of arbitrary duration.

Set @racket[#:open-after? #t] when the completed primary artifact should be
presented by the platform's ordinary file launcher. This is deliberately a
best-effort render-side action: unavailable desktop integration leaves the
artifact intact and records a warning in the execution report. An all-target
section export opens only the primary artifact, never a cascade of section
windows.

Cache identities are domain-specific. A frame identity includes source content,
the requested frame grid, effective camera, dimensions, supersampling, renderer
configuration, and declared visual/formula asset hashes. It intentionally
excludes output naming, encoder options, and audio assets: changing an MP4 CRF,
preset, or narration may require later work, but it does not require
rasterizing unchanged PNG frames again. Direct Scene values remain memory-only
because arbitrary embedded procedures cannot be fingerprinted honestly.

The @racket['segments] cache domain stores visual MP4 segments separately from
the frame domain. Its identity extends the frame identity with the codec,
pixel format, video options, frame rate, and selected FFmpeg release banner.
Audio cues and subtitles are intentionally excluded: final assembly remuxes
them after obtaining the visual segment, so narration edits do not re-encode
video. Several encoder profiles can coexist under the segment cache root. Set
@racket[cache-spec] to @racket['refresh] to replace a matching profile, or
remove @racket['segments] from its domains to encode without persistent segment
reuse. Use @tt{raco animate cache list PROJECT.rkt BINDING} to inspect the
target-specific roots. @tt{raco animate cache clear --domain segments
PROJECT.rkt BINDING} removes only cached video segments; omitting
@tt{--domain} clears the declared project cache root.

@racket[cache-spec]'s @racket[#:max-bytes] is a persistent-cache budget. After
a successful write, Animate removes the least-recently-used completed target
caches until the root is within the budget. It never deletes the target that
produced the current execution report, even if that target alone exceeds the
budget: its frame paths remain valid for the caller. The report records this as
a @racket['cache] cache event.
