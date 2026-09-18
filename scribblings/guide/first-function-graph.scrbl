#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/guide-examples.rkt"
          "../private/learning-illustrations.rkt")
@(define graph-eval (make-guide-eval))

@title[#:tag "guide-function-graph"]{Draw a graph}
@; requires: visual coordinates identity scene request duration sampling pict hold group

This lesson graphs @math{y=x^2/4-1}. It needs the Scene and group from the
earlier lessons, but no formula typesetter, calculus, or 3D camera. The examples
are evaluated while the manual is built. A complete standalone version is
@filepath{scribblings/examples/first-function-graph.rkt}.

@section[#:tag "guide-graph-axes"]{Choose the numbers and the drawing size}
@; introduces: axes numeric-range

An @bold{axis range} chooses numbers, not output pixels.
@racket[(axis-range -3 3 1)] runs from minus three to three, with a regular tick
step of one. The built-in Cartesian axes cross at zero, so each range includes
zero. @racket[#:x-length] and @racket[#:y-length] choose the lengths of the
drawn axes in world units. A numerical unit need not have the same drawn length
on both axes.

@examples[
 #:eval graph-eval
 #:no-result
 (require animate)
 (define coordinates
   (axes #:id 'coordinates
         #:x-range (axis-range -3 3 1)
         #:y-range (axis-range -2 2 1)
         #:x-length 7
         #:y-length 9/2
         #:stroke "navy"))
 (define axes-scene
   (scene-add (make-scene) coordinates))
]

Before adding a graph, look at the coordinate system itself:

@examples[
 #:eval graph-eval
 #:label #f
 (eval:alts
  (scene->pict axes-scene 0)
  (guide-pict (scene->pict axes-scene 0)))
]

The x range spans six numerical units and is drawn seven world units wide. The
y range spans four numerical units and is drawn 4.5 world units high. Tick
marks do not by themselves add text labels. The coordinate-decoration reference
describes how to add numeric labels when the picture needs them.

@section[#:tag "guide-graph-samples"]{Turn a function into a curve}
@; introduces: function-graph path-geometry

@racket[function-graph] evaluates a one-argument numerical function over the
chosen x range. It stores the resulting @bold{path geometry}: sampled points and
smooth cubic segments that will be drawn. Smooth interpolation is the default
for mathematical function graphs. A larger sample count gives the interpolator
more information; it is not a proof of accuracy.

@examples[
 #:eval graph-eval
 #:no-result
 (define curve
   (function-graph coordinates
                   (lambda (x) (- (/ (* x x) 4) 1))
                   #:id 'curve
                   #:sample-count 81
                   #:stroke "crimson"
                   #:stroke-width 3))
]

To inspect the stored result without animating it, put the axes and curve in a
temporary still Scene:

@examples[
 #:eval graph-eval
 #:label #f
 (eval:alts
  (scene->pict (scene-add (make-scene) coordinates curve) 0)
  (guide-pict
   (scene->pict (scene-add (make-scene) coordinates curve) 0)))
]

Try 21 samples instead of 81. The interpolation has less information about the
function, but its later two-second reveal still takes two seconds. Increasing
video frame rate does not add mathematical sample points to this stored curve.

This step constructs the curve. It does not play an animation and does not call
the function again for every movie frame. A later edit to the function requires
constructing a new graph. Use @racket[#:interpolation 'linear] when you
specifically want straight sample-to-sample segments; interpolation does not
change animation speed.

@section[#:tag "guide-graph-reveal"]{Draw the curve over time}
@; introduces: path-reveal

@racket[create] introduces a path Visual by revealing its geometry. The curve
must not already be present. Put the axes into the starting Scene, then reveal
the curve and hold the finished diagram:

@examples[
 #:eval graph-eval
 #:no-result
 (define drawing
   (scene-play axes-scene
               (create curve)
               #:duration 2))
 (define film
   (scene-wait drawing 1))
]

The durations below are checked during the documentation build:

@examples[
 #:eval graph-eval
 #:label #f
 (eval:check (scene-duration drawing) 2)
 (eval:check (scene-duration film) 3)
]

@learning-frames["draw-graph"]

The two-second reveal is followed by a one-second hold. Revealing a curve is
different from moving a point along it, and from changing the function itself.

@section[#:tag "guide-graph-group"]{Keep the graph with its axes}

The graph captured the axes' placement when it was constructed. It is not a
live dependency on the @racket[coordinates] variable. Moving only the axes later
would leave the graph behind. To move the finished diagram as one unit, group
the axes and curve:

@examples[
 #:eval graph-eval
 #:no-result
 (define diagram
   (group (list coordinates curve) #:id 'diagram))
 (define moving-diagram
   (scene-play (scene-add (make-scene) diagram)
               (move-to 'diagram (vec2 2 0))
               #:duration 2))
]

@examples[
 #:eval graph-eval
 #:label #f
 (eval:check (scene-duration moving-diagram) 2)
]

@learning-frames["move-graph"]

Here is the completed moved diagram:

@examples[
 #:eval graph-eval
 #:label #f
 (eval:alts
  (scene->pict moving-diagram 2)
  (guide-pict (scene->pict moving-diagram 2)))
]

This alternative starts with the complete curve already present. It does not
append to the reveal above. To move a diagram after a reveal, plan its shared
container and targeting before building the animation; the general grouping and
path rules are the same as in @secref["guide-objects"].

@section[#:tag "guide-graph-next"]{Choose the next step}

Use @racket[parametric-curve] when one parameter produces both coordinates.
Use @racket[data-plot] for an ordered list of observations. Look up those APIs
in @secref["geometry"], or return to the complete plotting example in the
Cookbook. Discontinuities and clipping require explicit choices; the simple
parabola above does not demonstrate those cases.

For titles, explanatory text, and a consistent page layout around a diagram,
continue with @secref["guide-slides"].

@close-eval[graph-eval]
