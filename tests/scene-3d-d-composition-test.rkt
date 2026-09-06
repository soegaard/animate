#lang racket/base

;;; SCENE-3D-D Composition Scheduling Tests

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt"
         "../main.rkt")

(define cube
  (mesh3d #:id 'cube
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define authored-camera
  (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3))

(define base-scene
  (scene-add
   (make-scene)
   (view3d (list cube) #:id 'world #:camera authored-camera #:render-mode 'opaque)
   (plain-text "A" #:id 'formula #:center (vec2 -2 2) #:font-size 1/2)))

(define (view-at scene time)
  (scene-state-ref (scene-sample scene time) 'world))

(define (cube-at scene time)
  (view3d-spatial-ref (view-at scene time) '(world cube)))

(module+ test
  ;; A succession is locally scheduled: the camera move completes before the
  ;; finite orbit starts, yet each frame is still sampled from its clip data.
  (define successive
    (scene-play
     base-scene
     (succession
      (camera3d-move-to 'world (vec3 2 0 6))
      (camera3d-orbit-by 'world #:azimuth (/ pi 2)))
     #:duration 4))
  (check-equal? (camera3d-position (view3d-camera (view-at successive 2)))
                (vec3 2 0 6))
  (check-not-equal? (view3d-camera (view-at successive 3))
                    (view3d-camera (view-at successive 2)))

  ;; The same pure 3D requests participate in parallel, staggered, and timed
  ;; compositions without widening the ordinary 2D request vocabulary.
  (define grouped
    (scene-play
     base-scene
     (animation-group
      (rotate3d-by '(world cube) (axis-angle y-axis3 pi))
      (camera3d-dolly-by 'world 1))
     #:duration 2))
  (check-equal?
   (transform3-rotation (spatial-transform (cube-at grouped 2)))
   (axis-angle y-axis3 pi))
  (check-equal? (camera3d-position (view3d-camera (view-at grouped 2)))
                (vec3 0 0 5))

  (define staggered
    (scene-play
     base-scene
     (lagged-start #:lag-ratio 1/2
                   (move3d-to '(world cube) (vec3 2 0 0))
                   (camera3d-move-to 'world (vec3 0 1 6)))
     #:duration 3))
  ;; The cube has begun before the camera's delayed interval, which catches a
  ;; scheduler that accidentally treats spatial leaves as non-composable.
  (check-true (positive?
               (vec3-x (transform3-translation
                         (spatial-transform (cube-at staggered 1))))))
  (check-equal? (camera3d-position (view3d-camera (view-at staggered 1)))
                (vec3 0 0 6))

  (define mixed
    (scene-play
     base-scene
     (timed (move3d-to '(world cube) (vec3 3 0 0)) #:start 1 #:duration 2)
     (timed (move-to 'formula (vec2 2 2)) #:start 0 #:duration 2)
     #:duration 4))
  (check-equal? (visual-position (scene-visual-at mixed 'formula 2))
                (vec2 2 2))
  (check-equal? (transform3-translation (spatial-transform (cube-at mixed 3)))
                (vec3 3 0 0)))
