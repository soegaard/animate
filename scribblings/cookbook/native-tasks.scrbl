#lang scribble/manual
@(require scribble/example
          (for-label racket/base
                     (only-in pict pict?)
                     animate
                     animate/3d))

@(define native-eval (make-base-eval))
@examples[#:eval native-eval #:hidden
  (require animate
           (only-in pict pict? [scale pict-scale] [frame pict-frame]))]

@title[#:tag "cookbook-native-tasks"]{Common Scene tasks}

Use these recipes after the first Scene lessons. Each code block is evaluated
when the manual is built. The small result below a recipe is also checked, so a
change in Animate that invalidates the example makes the documentation build
fail.

@section[#:tag "recipe-target-child"]{Move one part of a diagram}

Put related Visuals in a @racket[group], then address a child by its Visual path.
The destination is in the group's local coordinates.

@examples[#:eval native-eval #:no-result
  (define recipe-dot
    (circle #:id 'dot #:center (vec2 -1 0) #:radius 1/2
            #:fill "dodgerblue" #:stroke "navy"))
  (define recipe-tile
    (rectangle #:id 'tile #:center (vec2 1 0) #:width 1 #:height 1
               #:fill "gold" #:stroke "sienna"))
  (define recipe-pair
    (group (list recipe-dot recipe-tile) #:id 'pair #:center (vec2 1 0)))
  (define grouped-scene
    (scene-add (make-scene) recipe-pair))
  (define child-moves
    (scene-play grouped-scene
                (move-to '(pair dot) (vec2 -1 2))
                #:duration 2))]

Here is the completed movement. The documentation build evaluates the displayed
@racket[scene->pict] call; it only scales the resulting Pict for the page.

@examples[#:eval native-eval #:label #f
  (eval:alts
   (scene->pict child-moves 2)
   (pict-frame (pict-scale (scene->pict child-moves 2) 3/8)))]

@examples[#:eval native-eval #:label #f
  (eval:check (scene-duration child-moves) 2)
  (eval:check
   (visual-position (scene-state-ref (scene-sample child-moves 2) '(pair dot)))
   (vec2 -1 2))]

Do not confuse a Visual path such as @racket['(pair dot)] with a geometric
movement route. For the longer explanation, see @secref["guide-first-path"].

@section[#:tag "recipe-delay-start"]{Start the second animation later}

Use @racket[timed] when two requests share one play clip but start at different
times.

@examples[#:eval native-eval #:no-result
  (define delay-dot
    (circle #:id 'delay-dot #:center (vec2 -3 1) #:radius 1/2))
  (define delay-tile
    (rectangle #:id 'delay-tile #:center (vec2 -3 -1) #:width 1 #:height 1))
  (define delay-start
    (scene-add (make-scene) delay-dot delay-tile))
  (define delayed-scene
    (scene-play delay-start
                (timed (move-to 'delay-dot (vec2 3 1))
                       #:start 0 #:duration 2)
                (timed (move-to 'delay-tile (vec2 3 -1))
                       #:start 1/2 #:duration 2)
                #:duration 5/2))]

At @racket[3/2] seconds both objects are moving, but the second one started later:

@examples[#:eval native-eval #:label #f
  (eval:alts
   (scene->pict delayed-scene 3/2)
   (pict-frame (pict-scale (scene->pict delayed-scene 3/2) 3/8)))]

@examples[#:eval native-eval #:label #f
  (eval:check (scene-duration delayed-scene) 5/2)]

The outer duration includes the delay. For two non-overlapping steps, two
ordinary @racket[scene-play] calls are usually simpler. See
@secref["guide-overlap"].

@section[#:tag "recipe-restore-object"]{Bring a faded object back}

First decide whether the object is transparent or absent. @racket[fade-to]
changes opacity but keeps the target in the Scene; @racket[fade-out] removes it.

@examples[#:eval native-eval #:no-result
  (define restore-dot
    (circle #:id 'restore-dot #:center origin #:radius 1/2))
  (define restore-start
    (scene-add (make-scene) restore-dot))
  (define invisible
    (scene-play restore-start (fade-to 'restore-dot 0) #:duration 1))
  (define removed
    (scene-play restore-start (fade-out 'restore-dot) #:duration 1))]

Before comparing invisible and absent states, here is the object they start with:

@examples[#:eval native-eval #:label #f
  (eval:alts
   (scene->pict restore-start 0)
   (pict-frame (pict-scale (scene->pict restore-start 0) 3/8)))]

@examples[#:eval native-eval #:label #f
  (eval:check
   (scene-state-has? (scene-sample invisible 1) 'restore-dot)
   #t)
  (eval:check
   (scene-state-has? (scene-sample removed 1) 'restore-dot)
   #f)]

Restore the first with another opacity animation. Reintroduce the second with
@racket[fade-in]:

@examples[#:eval native-eval #:no-result
  (define visible-again
    (scene-play invisible (fade-to 'restore-dot 1) #:duration 1))
  (define reintroduced
    (scene-play removed (fade-in restore-dot) #:duration 1))]

@examples[#:eval native-eval #:label #f
  (eval:check
   (scene-state-has? (scene-sample visible-again 2) 'restore-dot)
   #t)
  (eval:check
   (scene-state-has? (scene-sample reintroduced 2) 'restore-dot)
   #t)]

See @secref["guide-hidden-vs-absent"] for the visual comparison.

@section[#:tag "recipe-graph-reveal"]{Reveal a mathematical graph}

Construct the curve first, leave it out of the initial Scene, and introduce it
with @racket[create].

@examples[#:eval native-eval #:no-result
  (define graph-axes
    (axes #:id 'graph-axes
          #:x-range (axis-range -3 3 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 7 #:y-length 9/2
          #:stroke "navy"))
  (define graph-curve
    (function-graph graph-axes
                    (lambda (x) (- (/ (* x x) 4) 1))
                    #:id 'graph-curve
                    #:sample-count 81
                    #:stroke "crimson"))
  (define graph-drawing
    (scene-play (scene-add (make-scene) graph-axes)
                (create graph-curve)
                #:duration 2))]

The completed reveal looks like this:

@examples[#:eval native-eval #:label #f
  (eval:alts
   (scene->pict graph-drawing 2)
   (pict-frame (pict-scale (scene->pict graph-drawing 2) 3/8)))]

@examples[#:eval native-eval #:label #f
  (eval:check (scene-duration graph-drawing) 2)
  (eval:check
   (scene-state-has? (scene-sample graph-drawing 2) 'graph-curve)
   #t)]

Do not add @racket[graph-curve] before calling @racket[create]. See
@secref["guide-function-graph"] for sampling and axis geometry.

@section[#:tag "recipe-sample-frame"]{Inspect a frame without making a movie}

When you want a picture rather than the semantic state, @racket[scene->pict]
is the direct route. It samples both the Scene and its ordinary camera at the
same time; no frame directory or encoder is involved.

@examples[#:eval native-eval #:label #f
  (eval:alts
   (scene->pict graph-drawing 1)
   (pict-frame (pict-scale (scene->pict graph-drawing 1) 3/8)))]

Use @racket[scene-sample] separately when you also need to inspect the semantic
state:

@examples[#:eval native-eval #:no-result
  (define middle-state (scene-sample graph-drawing 1))]

@examples[#:eval native-eval #:label #f
  (eval:check (scene-state? middle-state) #t)
  (eval:check (pict? (scene->pict graph-drawing 1)) #t)]

A 3D camera inside @racket[view3d] is part of that view instead of the ordinary
Scene camera.

@close-eval[native-eval]
