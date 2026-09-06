#lang racket/base

;;; SCENE-3D-F Direct Curve Animation Tests

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define curve
  (polyline3d (list origin3 (vec3 1 0 0) (vec3 1 1 0))
              #:id 'curve #:style (stroke3d #:width 3 #:color "tomato")))
(define marker (point3d origin3 #:id 'marker
                        #:style (point-style3d #:size 10 #:color "gold")))
(define world
  (view3d (list curve marker) #:id 'world #:render-mode 'opaque
          #:camera (perspective-camera3d #:position (vec3 2 2 6) #:look-at origin3)))

(define (sampled-view scene time)
  (scene-state-resolved-ref (scene-sample scene time) 'world))

(module+ test
  ;; `create` accepts an existing rooted curve path and begins visibly empty.
  (define created
    (scene-play (scene-add (make-scene) world) (create '(world curve)) #:duration 1))
  (define initial-curve (view3d-spatial-ref (sampled-view created 0) '(world curve)))
  (define final-curve (view3d-spatial-ref (sampled-view created 1) '(world curve)))
  (check-equal? (spatial-opacity initial-curve) 0)
  (check-equal? (spatial-opacity final-curve) 1)
  (check-equal? (curve3d-point-at final-curve 1) (vec3 1 1 0))

  ;; Curve motion and tangent orientation compile from the same immutable
  ;; source curve, so a direct final sample has the expected endpoint.
  (define moving
    (scene-play (scene-add (make-scene) world)
                (move-along-curve3d '(world marker) '(world curve))
                (orient-along-curve3d '(world marker) '(world curve))
                #:duration 2))
  (define final-marker
    (view3d-spatial-ref (sampled-view moving 2) '(world marker)))
  (check-equal? (spatial-position final-marker) (vec3 1 1 0))

  (define flashed
    (scene-play (scene-add (make-scene) world)
                (show-passing-flash '(world curve) #:time-width 1/4)
                #:duration 1))
  (define flash-view (sampled-view flashed 1/2))
  ;; A passing flash is an overlay, never a replacement for its source curve.
  (check-equal? (stroke3d-color
                 (curve3d-style (view3d-spatial-ref flash-view '(world curve))))
                "tomato")
  (check-equal?
   (stroke3d-color
    (curve3d-style (view3d-spatial-ref flash-view '(world curve--passing-flash))))
   "gold"))
