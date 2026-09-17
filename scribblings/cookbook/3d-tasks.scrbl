#lang scribble/manual
@(require scribble/example
          (for-label racket/base racket/math animate animate/3d)
          "../private/examples.rkt"
          "../private/three-d-illustrations.rkt")

@(define three-d-eval (make-base-eval))
@examples[#:eval three-d-eval #:hidden
  (require (only-in racket/math pi) animate animate/3d)]

@title[#:tag "cookbook-3d"]{3D objects and cameras}

For the step-by-step route, start at @secref["guide-3d-picture"]. The short
recipes here are executable. The complete multi-file lesson remains under
@filepath{scribblings/examples/} because the file relationships are part of
that example.

The following shared setup creates one spatial object inside a @racket[view3d]
and places that view in an ordinary Scene:

@examples[#:eval three-d-eval #:no-result
  (define brick
    (box3d 5/2 3/2 1
           #:id 'brick
           #:material (material3d #:color "cornflowerblue" #:shading 'flat)))
  (define model
    (view3d (list brick)
            #:id 'model
            #:width 10 #:height 45/8
            #:camera (perspective-camera3d
                      #:position (vec3 3 2 5)
                      #:look-at origin3)
            #:render-mode 'opaque
            #:background "aliceblue"))
  (define still
    (scene-add (make-scene) model))]

@examples[#:eval three-d-eval #:label #f
  (eval:check (spatial-visual? brick) #t)
  (eval:check (view3d? model) #t)]

@section[#:tag "recipe-3d-target"]{Move the object, not its window}

A rooted spatial path names the object inside its owning view. Use a @racket[vec3]
for the spatial destination:

@examples[#:eval three-d-eval #:no-result
  (define object-translation
    (scene-play still
                (move3d-to '(model brick) (vec3 1 0 0))
                #:duration 2))]

@examples[#:eval three-d-eval #:label #f
  (eval:check (scene-duration object-translation) 2)]

@three-d-frames["object-translation"]

Ordinary @racket[move-to] with @racket['model] and a @racket[vec2] moves the
entire rectangular viewport in the surrounding 2D composition.

@section[#:tag "recipe-3d-camera"]{Keep the object still and change the view}

Camera requests target the owning view ID, not the spatial child path:

@examples[#:eval three-d-eval #:no-result
  (define camera-motion
    (scene-play still
                (camera3d-orbit-by 'model #:azimuth (/ pi 2))
                #:duration 2))]

@examples[#:eval three-d-eval #:label #f
  (eval:check (scene-duration camera-motion) 2)]

@three-d-frames["camera-motion"]

The orbit changes the view's 3D camera. It does not rotate @racket[brick].

@section[#:tag "recipe-3d-complete"]{Use the complete three-file lesson}

These are intentionally external programs: the second and third files require
the first by a relative filename, so the file boundary is part of the example.
Requiring them creates descriptions, not videos or GUI windows.

@example-source["first-spatial-picture.rkt"]
@example-source["spatial-motion.rkt"]
@example-source["spatial-slides.rkt"]

@section[#:tag "recipe-3d-software"]{Use the ordinary software renderer}

The examples select filled faces with @racket[#:render-mode] @racket['opaque]; they do
not select OpenGL. Start with the software path. OpenGL is an explicit backend
choice, requires a suitable GUI process, and currently has its own one-worker
restriction. It is not the same restriction as the slide geometry adapter,
which supports the shared subprocess worker path.

@close-eval[three-d-eval]
