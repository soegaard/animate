#lang scribble/manual
@(require (for-label racket/base animate/slides)
          "../private/complete-examples.rkt")

@title[#:tag "complete-semantic-parts"]{Semantic matching of named parts}

Two words keep their identities while their positions change. A question fades
out and a conclusion fades in. The panel itself also moves to make room for
explanatory text. This example uses ordinary text; it needs no formula typesetter.

@complete-requirements["semantic-parts"]
@complete-frames["semantic-parts" "parts"]

@section[#:tag "complete-parts-source"]{Complete source}

@complete-source["scribblings/examples/matched-parts.rkt"]

@section[#:tag "complete-parts-structure"]{How the program is organized}

@racket[make-idea-panel] builds either arrangement from one function. The
@racket['observe] and @racket['explain] names remain the same on both sides.
The question and conclusion deliberately have different names, because one
leaves while the other enters.

The outer @racket['ideas] key connects the figure slots. Within the connected
figures, @racket[#:depth 'semantic] asks the transition to preserve the named
children. Their rectangles use a top-left origin: x goes right and y goes down.
Those are not the centred world coordinates used for ordinary Scene placement.

The movie holds for two seconds, transitions for 2.5, then holds for three.
Names establish correspondence; the declaration order and similar-looking words
do not replace those names.

@section[#:tag "complete-parts-run"]{Render the movie}

@complete-command["semantic-parts" "movie"]

@section[#:tag "complete-parts-change"]{Try one change}

Move a child to another rectangle while keeping its name. Then try changing the
name as well: that describes a different child, so it should enter or leave
instead of being retained. Use this distinction deliberately when explaining
whether an idea continues or is replaced.

See @secref["guide-named-parts"] and @secref["reference-semantic-content"].
