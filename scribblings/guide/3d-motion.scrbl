#lang scribble/manual
@(require (for-label racket/base
                     (only-in racket/math pi)
                     animate animate/3d)
          "../private/guide-examples.rkt"
          "../private/three-d-illustrations.rkt")
@(define motion3d-eval (make-guide-eval))

@title[#:tag "guide-3d-motion"]{Animate a 3D object and its camera}

@; requires: scene request hold view3d spatial-visual camera3d
Use the box and Scene from @secref["guide-3d-picture"]. The complete standalone
version of this chapter is @filepath{scribblings/examples/spatial-motion.rkt}.

Each short example below starts from the same @racket[still] Scene. They are
alternatives, not successive changes to one variable. The documentation
evaluator reconstructs that starting Scene privately and forces software 3D
rendering.

@examples[
 #:eval motion3d-eval
 #:hidden
 (require (only-in racket/math pi)
          animate animate/3d animate/3d/render)
 (define brick
   (box3d 5/2 3/2 1
          #:id 'brick
          #:material
          (material3d #:color "cornflowerblue"
                      #:shading 'flat)))
 (define viewpoint
   (perspective-camera3d
    #:position (vec3 3 2 5)
    #:look-at origin3))
 (define model
   (view3d (list brick)
           #:id 'model
           #:width 10 #:height 45/8
           #:camera viewpoint
           #:render-mode 'opaque
           #:background "aliceblue"))
 (define still
   (scene-add (make-scene) model))
 (define (guide-3d-pict thunk)
   (parameterize ([current-view3d-renderer3d (software-renderer3d)])
     (guide-pict (thunk))))
]

@section[#:tag "guide-3d-turn-object"]{Turn the object inside the view}
@; introduces: spatial-path spatial-motion

A @bold{spatial path} names an object inside a view. The path
@racket['(model brick)] starts with the view's ID and ends with the object's ID.
Use it when the object should change but the surrounding window should stay put.

@racket[axis-angle] makes a rotation from an axis and an angle in radians.
@racket[y-axis3] is the positive y axis. An angle of @racket[(/ pi 2)] is a
quarter turn. This is an orientation change, not a count of repeated full turns.

@examples[
 #:eval motion3d-eval
 #:no-result
 (define object-motion
   (scene-play still
               (rotate3d-by '(model brick)
                            (axis-angle y-axis3 (/ pi 2)))
               #:duration 2))
]

@examples[
 #:eval motion3d-eval
 #:label #f
 (eval:check (scene-duration object-motion) 2)
]

@three-d-frames["object-motion"]

The box turns; its 3D camera and the rectangle containing the picture remain
unchanged. @racket[scene-play] supplies the duration just as it did in 2D.

To change the box's position instead, use a 3D point:

@examples[
 #:eval motion3d-eval
 #:no-result
 (define translated-object
   (scene-play still
               (move3d-to '(model brick) (vec3 1 0 0))
               #:duration 2))
]

@three-d-frames["object-translation"]

This moves the box in the view's spatial coordinate system. Use
@racket[group3d] to move several objects together. Each child then has a
position relative to that group. A path through a group might be
@racket['(model assembly brick)].

@section[#:tag "guide-3d-orbit-camera"]{Move the camera around the object}
@; introduces: camera3d-motion

A camera request names only the owning view, @racket['model].
@racket[camera3d-orbit-by] moves the 3D camera around a point while keeping it
looking at that point. Its default centre is the origin. @racket[#:azimuth] is
the horizontal orbit angle, in radians.

@examples[
 #:eval motion3d-eval
 #:no-result
 (define camera-motion
   (scene-play still
               (camera3d-orbit-by 'model #:azimuth (/ pi 2))
               #:duration 2))
]

@examples[
 #:eval motion3d-eval
 #:label #f
 (eval:check (scene-duration camera-motion) 2)
]

@three-d-frames["camera-motion"]

The box itself has not moved. It looks different because we see it from another
side. The window stays at the same place on the page.

@section[#:tag "guide-3d-move-panel"]{Move the whole window}

The view is an ordinary 2D Visual, so ordinary @racket[move-to] moves the whole
window. This time the target is @racket['model] and the destination is a
@racket[vec2], not a @racket[vec3].

@examples[
 #:eval motion3d-eval
 #:no-result
 (define panel-motion
   (scene-play still
               (move-to 'model (vec2 2 0))
               #:duration 2))
]

@three-d-frames["panel-motion"]

The box and its camera keep their relationship. Only the placement of their
picture within the surrounding Scene changes.

@tabular[#:sep @hspace[1]
 (list
  (list @bold{Change} @bold{Target} @bold{Operation})
  (list "Box position" @racket['(model brick)] @racket[move3d-to])
  (list "Box orientation" @racket['(model brick)] @racket[rotate3d-by])
  (list "3D viewpoint" @racket['model] @racket[camera3d-orbit-by])
  (list "Window on the page" @racket['model] @racket[move-to]))]

@section[#:tag "guide-3d-small-lesson"]{Build a complete six-second sequence}

First turn the object for two seconds. Hold it for one second. Then orbit the
camera for two seconds and hold again. A small function lets us reuse this timing
with or without a surrounding heading:

@examples[
 #:eval motion3d-eval
 #:no-result
 (define (make-lesson initial)
   (define turn
     (scene-play initial
                 (rotate3d-by '(model brick)
                              (axis-angle y-axis3 (/ pi 2)))
                 #:duration 2))
   (define read-turn
     (scene-wait turn 1))
   (define orbit
     (scene-play read-turn
                 (camera3d-orbit-by 'model #:azimuth (/ pi 2))
                 #:duration 2))
   (scene-wait orbit 1))
 (define lesson
   (make-lesson still))
]

The timing claim is executable:

@examples[
 #:eval motion3d-eval
 #:label #f
 (eval:check (scene-duration lesson) 6)
 (eval:alts
  (scene->pict lesson 6)
  (guide-3d-pict (lambda () (scene->pict lesson 6))))
]

@three-d-frames["lesson"]

The @racket[lesson] value is an ordinary Scene. Use the frame and MP4 commands
from @secref["guide-rendering-a-video"] with this value. Add a final hold
whenever the finished picture needs time on screen: a video's frame grid does
not normally include the exact endpoint as an extra frame.

The software renderer works without an OpenGL window. OpenGL is a separate,
optional rendering choice with its own restrictions; it is not required for any
example in this route. Next, @secref["guide-3d-composition"] adds text and a
slide.

@close-eval[motion3d-eval]
