#lang racket/base

;;; SCENE-3D-D Deterministic Sampling Tests

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt"
         "../main.rkt")

(define cube
  (mesh3d #:id 'cube
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define scene
  (scene-play
   (scene-add
    (make-scene)
    (view3d (list cube) #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 6)
                                           #:look-at origin3)))
   (rotate3d-by '(world cube) (axis-angle y-axis3 (* 2 pi)))
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 12))
   #:duration 3))

(module+ test
  ;; Nonmonotone requests must agree with a fresh direct request for the same
  ;; time.  No frame carries integration or camera-navigation history.
  (define at-one-first (scene-sample scene 1))
  (void (scene-sample scene 2))
  (void (scene-sample scene 1/3))
  (define at-one-again (scene-sample scene 1))
  (check-equal? at-one-again at-one-first)
  (check-equal? (scene-sample scene 0) (scene-sample scene 0))
  (check-equal? (scene-sample scene 3) (scene-sample scene 3)))
