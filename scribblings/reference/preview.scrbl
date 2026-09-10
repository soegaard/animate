#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/authoring
                     (except-in animate/colors tan)
                     animate/project
                     animate/preview))

@title[#:tag "reference-preview"]{Interactive Preview and Inspection}

@declare-exporting[animate/preview]

@racketmodname[animate/preview] provides the optional GUI and its headless
controller API.  Requiring it does not initialize a GUI; opening a window does.
It uses the same scene sampling and rendering semantics as final output.

@defproc[(animation-inspection? [value any/c]) boolean?]{Recognizes an
immutable active-animation inspection record re-exported by the preview API.}

@defproc[(animation-inspection-kind [inspection animation-inspection?]) any/c]{Returns
the animation request-family symbol retained by @racket[inspection].}

@defproc[(animation-inspection-data [inspection animation-inspection?]) any/c]{Returns
the immutable semantic explanation data retained by @racket[inspection].}

@defproc[(preview-session? [value any/c]) boolean?]{
Recognizes a live preview controller session.
}

@defproc[(preview-status? [value any/c]) boolean?]{
Recognizes the immutable status snapshot returned by preview configuration and
transport operations.
}

@defproc[(open-scene-preview [source (or/c scene? authored-timeline?)]
                             [#:fps fps exact-positive-integer? 30]
                             [#:theme theme (or/c false/c color-theme?) #f]
                             [#:typography typography (or/c false/c typography-theme?) #f]
                             [#:pixel-scale pixel-scale positive? 1]
                             [#:cache-megabytes cache-megabytes exact-positive-integer? 512]
                             [#:prefetch prefetch exact-nonnegative-integer? 3]
                             [#:render-workers render-workers exact-positive-integer? 1]
                             [#:title title string? "Animate"])
         preview-session?]{
Opens an interactive preview with immutable color and typography snapshots.
They affect rendered scene pixels only: canvas handles, inspector text, and
operating-system widgets retain their editor UI appearance. The bitmap cache
uses 512 MiB by default. @racket[#:render-workers] normally remains 1: it is
for producers that explicitly provide isolated render processes, not for an
ordinary in-process scene or an OpenGL context.
}

@defproc[(inspector-subject? [value any/c]) boolean?]{
Recognizes an immutable semantic inspection subject.
}

@defproc[(inspector-document? [value any/c]) boolean?]{
Recognizes an immutable GUI-independent inspector snapshot.
}

@defproc[(open-program-preview [module-path path-string?]
                               [binding symbol?]
                               [#:auto-reload? auto-reload? boolean? #t]
                               [#:fps fps exact-positive-integer? 30]
                               [#:start start (or/c #f real?) #f]
                               [#:start-block start-block (or/c #f symbol?) #f]
                               [#:section section (or/c #f symbol?) #f]
                               [#:pixel-scale pixel-scale positive? 1]
                               [#:repl? repl? boolean? #f]
                               [#:title title string? "Animate"])
         preview-session?]{

Loads a module binding containing a @racket[scene-program?], compiles it, and
opens a hot-reloading preview.  At most one of @racket[#:start] and
@racket[#:start-block] may be supplied.  Run the containing program with
GRacket (or @tt{raco animate preview}) rather than a headless Racket process.
}

@defproc[(open-project-preview [project animate-project?]
                               [#:target target project-target? (project-target-all)]
                               [#:directory directory path-string? (current-directory)]
                               [#:title title (or/c #f string?) #f])
         preview-session?]{

Prepares and opens an immutable project declaration. A module-binding source
uses ten restartable software-renderer subprocesses, so queued independent
frames can use up to ten CPU cores. The @tt{software workers} preview menu
selects how many of those lanes receive new work. Direct Scene or timeline sources use
cooperative in-process cancellation. An OpenGL project keeps one serialized
graphics context.
}

@defproc[(preview-color-theme [session preview-session?]) color-theme?]{
Returns the immutable theme snapshot selected for this session's video content.
}

@defproc[(preview-set-color-theme! [session preview-session?]
                                   [theme color-theme?])
         preview-status?]{
Changes only the preview content theme. The session keeps its semantic time,
selection, audio position, and inspection-camera overrides, but advances its
render generation and uses separately keyed frame-cache entries. A bitmap from
the previous theme can never be installed as a result for the new theme.
}

@defproc[(preview-typography-theme [session preview-session?]) typography-theme?]{
Returns the typography snapshot selected for this session's semantic text.}

@defproc[(preview-set-typography-theme! [session preview-session?]
                                        [typography typography-theme?])
         preview-status?]{
Changes only the preview typography snapshot. The preview keeps its semantic
time and selection. If the new snapshot has a different typography appearance,
the preview advances its render generation and never reuses a bitmap from the
earlier appearance. If only metadata such as the theme name or provenance
changes, the current bitmap and render generation are retained while inspector
metadata is updated.
}

@defproc[(preview-scrub! [session preview-session?] [time real?]) void?]{
Seeks during a drag.  Older pending scrub work is superseded and the current
time first uses the preview's draft quality.
}

@defproc[(preview-render-worker-count [session preview-session?])
         exact-positive-integer?]{
Returns the number of renderer lanes that may receive new work concurrently.
}

@defproc[(preview-set-render-worker-count! [session preview-session?]
                                            [count exact-positive-integer?])
         preview-status?]{
Sets the renderer-lane limit, up to the session's pre-created worker pool.
Existing jobs finish; the new limit applies when the scheduler chooses its next
jobs. Module-backed project previews expose this as the @tt{software workers}
menu.
}

@defproc[(preview-play! [session preview-session?]) void?]{Starts playback.}

@defproc[(preview-set-loop-range! [session preview-session?]
                                  [start real?]
                                  [end real?])
         void?]{
Stores a half-open loop range.  It applies to both visual playback and an
available project audio monitor.
}

@defproc[(preview-jump-to-section! [session preview-session?] [name symbol?])
         void?]{Jumps to the named authored section.}

@defproc[(preview-jump-to-cue! [session preview-session?] [name symbol?])
         void?]{Jumps to the named authored cue.}

@defproc[(preview-session-diagnostics [session preview-session?]) immutable-hash?]{
Returns one immutable production-monitor snapshot: requested and displayed
sample times, quality, cache state, cancellation count, worker information,
recent rendering measurements, and the color/typography appearance
fingerprints plus resolver versions used by the current frame-cache namespace.
}

@defproc[(scene-inspector-subject-at-path [state scene-state?]
                                          [path visual-path?])
         inspector-subject?]{

Builds a stable inspector subject for a sampled Visual path.  It promotes a
uniquely mapped formula leaf to its precise source-map unit and never guesses
between repeated or shared source occurrences.
}

@defproc[(scene-inspector-document [scene scene?]
                                   [time real?]
                                   [#:subject subject (or/c #f inspector-subject?) #f]
                                   [#:theme theme color-theme? animate-light-theme]
                                   [#:typography typography typography-theme?
                                                 animate-typography-theme])
         inspector-document?]{

Creates the immutable, GUI-independent inspector model for a scene sample.
Formula maps, active string-match plans, relation dependency reports, camera,
and preview-only overlays all live in this value; inspecting does not invalidate
the bitmap cache. When the selected object is semantic text, its Typography
section distinguishes the authored role and overrides from the base style and
resolved appearance. It also reports the resolved color and measured rendered
box under the selected theme and typography snapshots.
}

@bold{Limitations:} hard cancellation is available only for a module-backed
project worker.  An arbitrary direct Scene can contain an opaque Racket
procedure, so it is cancelable only at cooperative rendering boundaries.  Audio
monitoring is optional and requires a usable @tt{ffplay} installation.
