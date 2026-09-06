#lang racket/base

(require rackunit
         racket/class
         racket/draw
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (_x _y _z) (vec3 1 1/2 0))
     (vec3 -1 -1 0) #:time-range (cons 0 2) #:step-size 1/10))
  (define phase (parameter 'phase 0))
  (define scene
    (scene-play
     (scene-add
      (scene-set-value (make-scene) phase)
      (view3d
       (list (streamline3d (lambda (_x _y _z) (vec3 1 1/2 0))
                           (vec3 -1 -1 0) #:id 'trace #:steps 20 #:step-size 1/10
                           #:radius 1/35 #:color "royalblue")
             ;; Endpoint magnitude colours exercise saturated per-vertex RGB
             ;; through the opaque lighting pipeline.
             (vector-field3d (lambda (x _y _z) (vec3 (+ 2 x) 0 0))
                             #:id 'field
                             #:x-range '(-1 1) #:y-range '(0 0) #:z-range '(0 0)
                             #:x-count 2 #:y-count 1 #:z-count 1
                             #:color-by-magnitude? #t #:radius 1/20)
             (flow-particle3d trajectory phase #:id 'particle #:radius 1/10
                              #:tangent-length 2/5))
       #:id 'world #:width 5 #:height 3 #:render-mode 'opaque
       #:camera (perspective-camera3d #:position (vec3 3 3 6)
                                      #:look-at origin3)))
     (value-to phase 2) #:duration 1))
  (define first (scene-frame->bitmap scene 0 #:fps 2))
  (define second (scene-frame->bitmap scene 1 #:fps 2))
  (check-true (is-a? first bitmap%))
  (check-true (is-a? second bitmap%)))
