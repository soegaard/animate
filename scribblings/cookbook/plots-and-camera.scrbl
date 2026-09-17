#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "recipe-plots-and-camera"]{Draw plots while moving the camera}

This is an advanced recipe, not a first example. Read the moving-circle
Quick Start before using it. The complete API is in Reference.

@declare-exporting[animate #:use-sources (animate/main)]

The following program builds Cartesian axes, samples a coordinate-valued
parametric procedure, plots one ordered data series, and animates the camera at
the same time. Both curves use smooth cubic interpolation and the ordinary path
@racket[create] animation.

@racketmod[
racket/base

(require animate)

;; Frame and media output is deliberately a separate effectful module.
(require animate/render)

(define coordinate-axes
  (axes #:id 'coordinate-axes
        #:x-range (axis-range -4 4 1)
        #:y-range (axis-range -3 3 1)
        #:x-length 8
        #:y-length 6
        #:stroke "navy"))

(define loop-curve
  (parametric-curve
   coordinate-axes
   (lambda (parameter)
     (define x
       (- (* parameter parameter) 2))
     (vec2 x (/ (* parameter x) 2)))
   #:id 'loop-curve
   #:parameter-range (parameter-range -2 2)
   #:sample-count 181
   #:interpolation 'smooth
   #:stroke "crimson"))

(define observations
  (data-plot
   coordinate-axes
   (list (vec2 -3 -3/2)
         (vec2 -2 1/2)
         (vec2 -1 1)
         (vec2 0 1/4)
         (vec2 1 -1)
         (vec2 2 -1/2)
         (vec2 3 3/2))
   #:id 'observations
   #:interpolation 'smooth
   #:stroke "seagreen"))

(define initial-camera
  (make-camera #:world-width 14
               #:center origin))

(define animation
  (scene-wait
   (scene-play (make-scene #:camera initial-camera)
               (fade-in coordinate-axes)
               (create loop-curve)
               (create observations)
               (camera-pan-to (vec2 1 0))
               (camera-zoom-by 3/2)
               #:duration 2)
   1/2))

(render-frames! animation "frames" #:fps 30)
]

@racket[parametric-curve] calls the procedure while constructing the Visual.
It stores only immutable path geometry and a snapshot of the axes transform.
Rendering later frames does not call the procedure or read the original data
list again. The camera center and visible width are sampled from the same scene
clip as the Visual animations.

The call to @racket[render-frames!] creates numbered PNG files. To assemble them
as an MP4 file, install FFmpeg and call:

@racketblock[
(encode-mp4! "frames" "animation.mp4" #:fps 30)
]
