#lang scribble/manual
@(require (for-label racket/base
                     animate/slides
                     animate/slides/pict
                     animate/slides/render
                     animate/slides/geometry)
          "../private/guide-examples.rkt"
          "../private/examples.rkt"
          "../private/illustrations.rkt")
@(define semantic-eval (make-guide-eval))

@title[#:tag "guide-semantic-continuity"]{Keep parts connected across slides}
@; requires: continuity-key transition storyboard theme easing viewport content-clock preparation math-plan construction

A title match moves one retained object. There are two ways to retain more
structure: name the parts inside an object, or use checkpoints from one existing
animation. These solve different problems.

The named-part example is pure slide content, so this chapter executes it
directly. Domain-specific math and geometry checkpoint examples remain
file-backed examples because they are also exercised by their dedicated
preparation and visual-probe pipelines.

@examples[
 #:eval semantic-eval
 #:hidden
 (require animate/slides
          animate/slides/pict
          animate/slides/render)
]

@section[#:tag "guide-named-parts"]{Name the parts you want to follow}
@; introduces: semantic-group semantic-part part-coordinates

A @racket[semantic-group] contains named @racket[semantic-part] children. Each
child gets a rectangle in the group's coordinates. Unlike ordinary Scene
centres, these rectangles start at the @bold{top-left}: x goes right, y goes
down.

The function below makes two arrangements. @racket[#f] selects the first;
@racket[#t] selects the second. The words @racket["Observe"] and
@racket["Explain"] keep their names, while @racket['question] is replaced by
the new child @racket['conclusion].

@examples[
 #:eval semantic-eval
 #:no-result
 (define (make-idea-panel final?)
   (define row
     (semantic-group #:width 10 #:height 3
       (semantic-part 'observe "Observe"
                      #:x (if final? 6 0)
                      #:y 0 #:width 4 #:height 1.2)
       (semantic-part 'explain "Explain"
                      #:x (if final? 0 6)
                      #:y 1.6 #:width 4 #:height 1.2)))
   (semantic-group #:width 12 #:height 6
     (semantic-part 'ideas row
                    #:x (if final? 0 1)
                    #:y (if final? 1.4 0.4)
                    #:width (if final? 9 10)
                    #:height 3)
     (semantic-part (if final? 'conclusion 'question)
                    (if final?
                        "Connect the ideas."
                        "What do we notice?")
                    #:x 1 #:y 4.5 #:width 10 #:height 1)))
]

Now place those arrangements in slots with the same outer continuity key:

@examples[
 #:eval semantic-eval
 #:no-result
 (define before
   (slide #:layout 'title+figure
     [title "The parts keep their identities"]
     [figure #:key 'ideas (make-idea-panel #f)]))
 (define after
   (slide #:layout 'title+figure
     [title "The parts keep their identities"]
     [body "The panel moves. Its named children rearrange independently."]
     [figure #:key 'ideas (make-idea-panel #t)]))
]

@racket[#:depth 'semantic] asks for a supported inner correspondence, not merely
whole-slot movement. The figure moves and the named children rearrange:
@; introduces: matching-depth

@examples[
 #:eval semantic-eval
 #:no-result
 (define parts-film
   (storyboard #:id 'manual-parts #:theme lecture-dark
     (storyboard-shot 'before
                      (hold-slide before #:duration 2))
     (slide-transition #:effect 'match
                       #:keys '(ideas)
                       #:depth 'semantic
                       #:duration 2.5
                       #:easing 'smooth)
     (storyboard-shot 'after
                      (hold-slide after #:duration 3))))
]

@frame-strip["semantic-parts"]

Matching uses names, not similar-looking text or declaration order. A group can
contain another group; child names are scoped by their parent. A changed
appearance crossfades inside its moving rectangle. Newly added children fade in;
removed children fade out.

The preparation and match report are also executable for this text-only example:

@examples[
 #:eval semantic-eval
 #:no-result
 (define prepared-parts
   (prepare-storyboard! parts-film))
 (define parts-report
   (storyboard-match-report prepared-parts))
]

@examples[
 #:eval semantic-eval
 #:label #f
 (eval:check (prepared-storyboard? prepared-parts) #t)
 (eval:check (pair? parts-report) #t)
 (eval:alts
  (storyboard->pict prepared-parts #:at 13/4)
  (guide-pict
   (storyboard->pict prepared-parts #:at 13/4)))
]

The still above is sampled halfway through the 2.5-second semantic bridge.

@section[#:tag "guide-checkpoint"]{Freeze a point in an existing animation}

A @bold{checkpoint}, made with @racket[content-state], freezes an existing
content source at a selected local time. This is different from a playing
figure. Use the equation and plan from @secref["guide-math-content"].

Both checkpoints below use the same twelve-by-seven @bold{canonical viewport}.
That shared local window lets the outer slide layout change without typesetting
two unrelated versions of the equation.
@; introduces: checkpoint canonical-viewport

These definitions remain sourced from the complete maintained program, rather
than duplicating the mathematical derivation in this chapter:

@example-part["math-checkpoints.rkt" "before"]
@example-part["math-checkpoints.rkt" "after"]

@section[#:tag "guide-checkpoint-replay"]{Replay the known interval while changing the layout}

The match below advances the original math plan from the first checkpoint to
the second while it moves the figure. It does not guess algebra from two
pictures.

@example-part["math-checkpoints.rkt" "match"]
@frame-strip["semantic-math"]

During the held shots, each checkpoint is still. Only the bridge advances the
selected child interval. The equation ends at @tt{3x = 12}; this example is not
yet the complete solution @tt{x = 4}.

@section[#:tag "guide-geometry-checkpoint"]{The same idea works for a construction}

Use checkpoints from one @racket[geometry-content] value. In the gallery, the
first checkpoint is @racket['(1 end)], after the two given points have
appeared; the second is @racket['end]. That is why the starting picture is not
an empty viewport.

@racketblock[
(define construction
  (geometry-content equilateral-triangle))

(define before
  (content-state construction
                 #:at '(1 end)
                 #:viewport '(12 7)))

(define after
  (content-state construction
                 #:at 'end
                 #:viewport '(12 7)))
]

@frame-strip["semantic-geometry"]

These frames are from @racket['semantic-geometry] in the gallery. The original
construction controls the circles, lines, and labels throughout the bridge. It
is not a morph between independently solved constructions.

@section[#:tag "guide-multi-domain-match"]{Let two domains advance in one bridge}

A named group can contain both the mathematical checkpoint and the construction
checkpoint. Each retains its own identity and local interval while the outer
panel changes arrangement. The @racket['semantic-math-geometry] gallery example
does this; it is not a second animation engine.

@frame-strip["semantic-math-geometry"]

To render that complete example, see @secref["recipe-gallery-select"]. Its
source is @filepath{slides/examples/gallery/semantic-domains.rkt}.

@section[#:tag "guide-match-report"]{Choose the strictness and inspect the result}

@racket[#:depth 'auto], the default, uses supported inner matching and otherwise
falls back to ordinary matching or a crossfade. @racket[#:depth 'semantic]
reports unsupported correspondence. @racket[#:depth 'slot] keeps the older
whole-slot policy.

The earlier @racket[parts-report] is the result of
@racket[(storyboard-match-report prepared-parts)]. It describes what was
matched, replayed, or left to a fallback. Reduced motion crossfades the frozen
endpoints without replay. Replay is visual-only; it does not copy or stretch
narration. See @secref["reference-semantic-content"] for the full contracts.

@close-eval[semantic-eval]
