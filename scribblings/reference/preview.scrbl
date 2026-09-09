#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
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
                             [#:pixel-scale pixel-scale positive? 1]
                             [#:title title string? "Animate"])
         preview-session?]{
Opens an interactive preview with one immutable content-theme snapshot. The
theme affects rendered scene pixels only: canvas handles, inspector text, and
operating-system widgets retain their editor UI appearance.
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

Prepares and opens an immutable project declaration.  A module-binding source
uses a restartable subprocess renderer; direct Scene or timeline sources use
cooperative in-process cancellation.
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

@defproc[(preview-scrub! [session preview-session?] [time real?]) void?]{
Seeks during a drag.  Older pending scrub work is superseded and the current
time first uses the preview's draft quality.
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
and recent rendering measurements.
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
                                   [#:subject subject (or/c #f inspector-subject?) #f])
         inspector-document?]{

Creates the immutable, GUI-independent inspector model for a scene sample.
Formula maps, active string-match plans, relation dependency reports, camera,
and preview-only overlays all live in this value; inspecting does not invalidate
the bitmap cache.
}

@bold{Limitations:} hard cancellation is available only for a module-backed
project worker.  An arbitrary direct Scene can contain an opaque Racket
procedure, so it is cancelable only at cooperative rendering boundaries.  Audio
monitoring is optional and requires a usable @tt{ffplay} installation.
