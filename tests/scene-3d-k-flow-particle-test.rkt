#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../private/3d/ode-flow3d.rkt")

(module+ test
  (define calls (box 0))
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (_x _y _z)
       (set-box! calls (add1 (unbox calls)))
       x-axis3)
     origin3 #:time-range (cons 0 1) #:step-size 1 #:checkpoint-every 1))
  (define phase (parameter 'phase 0))
  (define particle
    (flow-particle3d trajectory phase #:id 'particle #:tangent-length 1/2))
  (check-true (spatial-relation? particle))
  (define world
    (view3d (list particle) #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 2 2 5) #:look-at origin3)))
  (define animation
    (scene-play
     (scene-add (scene-set-value (make-scene) phase) world)
     (value-to phase 1) #:duration 1))
  (define state (scene-sample animation 1/2))
  ;; Preparation executes all required field calls before spatial relation
  ;; resolution.  The later sampled view reads only the immutable frame table.
  (set-box! calls 0)
  (define samples (prepare-ode3d-frame-samples (list state)))
  (check-true (positive? (unbox calls)))
  (set-box! calls 0)
  (call-with-ode3d-frame-samples
   samples
   (lambda ()
     (define resolved-world (scene-state-resolved-ref state 'world))
     (define resolved-particle
       (view3d-spatial-ref resolved-world '(world particle)))
     (check-true (group3d? resolved-particle))))
  (check-equal? (unbox calls) 0))
