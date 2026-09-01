#lang racket/base

;;;
;;; SCENE-Z Path Orientation Model Tests
;;;

;; Tests path tangents and normals, normal-offset motion, tangent-aligned
;; rotation, reverse traversal, transformed path Visual routes, component
;; conflicts, and camera following of the final offset target position.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require (only-in racket/math pi)
         rackunit
         "../private/animation.rkt"
         "../private/camera-animation.rkt"
         "../private/camera.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; unequal-route : path-geometry?
  ;;   Gives a three-unit horizontal edge followed by a four-unit vertical edge.
  (define unequal-route
    (polyline-path
     (list origin
           (vec2 3 0)
           (vec2 3 4))))

  ;; Tangents and normals use the same total arc-length fractions as point
  ;; lookup. An exact edge boundary retains the preceding traversal edge.
  (check-equal? (path-geometry-tangent-at unequal-route 0)
                (vec2 1 0))
  (check-equal? (path-geometry-tangent-at unequal-route 3/7)
                (vec2 1 0))
  (check-equal? (path-geometry-tangent-at unequal-route 1/2)
                (vec2 0 1))
  (check-equal? (path-geometry-tangent-at unequal-route 1)
                (vec2 0 1))
  (check-equal? (path-geometry-normal-at unequal-route 1/7)
                (vec2 0 1))
  (check-equal? (path-geometry-normal-at unequal-route 1/2)
                (vec2 -1 0))

  ; curved-cubic : path-geometry?
  ;;   Gives a symmetric arch with a horizontal tangent at half arc length.
  (define curved-cubic
    (cubic-bezier-path
     (vec2 -1 0)
     (list
      (cubic-bezier-path-segment
       (vec2 -1 1)
       (vec2 1 1)
       (vec2 1 0)))))
  (define curved-tangent
    (path-geometry-tangent-at curved-cubic 1/2))
  (check-= (vec2-x curved-tangent) 1 1e-10)
  (check-= (vec2-y curved-tangent) 0 1e-10)

  ; stationary-start-cubic : path-geometry?
  ;;   Has zero derivative at t=0 but a well-defined forward traversal direction.
  (define stationary-start-cubic
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       origin
       origin
       (vec2 2 0)))))
  (check-equal? (path-geometry-tangent-at stationary-start-cubic 0)
                (vec2 1 0))

  ; stationary-end-cubic : path-geometry?
  ;;   Has zero derivative at t=1 but a well-defined incoming traversal direction.
  (define stationary-end-cubic
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       (vec2 2 0)
       (vec2 2 0)
       (vec2 2 0)))))
  (check-equal? (path-geometry-tangent-at stationary-end-cubic 1)
                (vec2 1 0))

  ;; A closed subpath's implicit closing edge is part of the tangent model.
  (define closed-route
    (polygon-path
     (list origin
           (vec2 2 0)
           (vec2 2 2))))
  (define closing-tangent
    (path-geometry-tangent-at closed-route 1))
  (define inv-sqrt2
    (/ 1 (sqrt 2)))
  (check-= (vec2-x closing-tangent) (- inv-sqrt2) 1e-12)
  (check-= (vec2-y closing-tangent) (- inv-sqrt2) 1e-12)

  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-tangent-at empty-path-geometry 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-normal-at unequal-route 2)))

  ; marker : rectangle-visual?
  ;;   Gives an asymmetric affine target so rotation is semantically visible.
  (define marker
    (rectangle #:id 'marker
               #:center origin
               #:width 1
               #:height 1/2
               #:fill "crimson"))

  ;; Public request constructors expose path-relative translation and rotation.
  (check-true
   (move-along-path-request?
    (move-along-path marker unequal-route #:normal-offset 1)))
  (check-true
   (orient-along-path-request?
    (orient-along-path marker unequal-route)))
  (check-true
   (orient-along-path-request?
    (orient-along-path 'marker
                       unequal-route
                       #:start 1
                       #:end 0
                       #:rotation-offset (/ pi 4))))
  (check-exn exn:fail:contract?
             (lambda ()
               (move-along-path marker
                                unequal-route
                                #:normal-offset +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (orient-along-path marker
                                  unequal-route
                                  #:rotation-offset +nan.0)))

  ; offset-scene : scene?
  ;;   Moves one world unit to the left of the forward traversal direction.
  (define offset-scene
    (scene-play
     (scene-add (make-scene) marker)
     (move-along-path marker unequal-route #:normal-offset 1)
     #:duration 7))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample offset-scene 1) 'marker))
   (vec2 1 1))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample offset-scene 7/2) 'marker))
   (vec2 2 1/2))

  ; reverse-marker : rectangle-visual?
  ;;   Begins at the route end for reverse offset and orientation checks.
  (define reverse-marker
    (rectangle #:id 'reverse-marker
               #:center (vec2 3 4)
               #:width 1
               #:height 1/2))
  (define reverse-offset-scene
    (scene-play
     (scene-add (make-scene) reverse-marker)
     (move-along-path reverse-marker
                      unequal-route
                      #:start 1
                      #:end 0
                      #:normal-offset 1)
     #:duration 7))
  ;; At half progress the raw route point is (3, 1/2). Reverse motion points
  ;; downward, so its left normal points toward positive x.
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample reverse-offset-scene 7/2)
                     'reverse-marker))
   (vec2 4 1/2))

  ; oriented-scene : scene?
  ;;   Moves and rotates one target from horizontal into vertical traversal.
  (define oriented-scene
    (scene-play
     (scene-add (make-scene) marker)
     (move-along-path marker unequal-route)
     (orient-along-path marker unequal-route)
     #:duration 7))
  (define oriented-horizontal
    (scene-state-ref (scene-sample oriented-scene 2) 'marker))
  (define oriented-vertical
    (scene-state-ref (scene-sample oriented-scene 4) 'marker))
  (check-equal? (visual-position oriented-horizontal)
                (vec2 2 0))
  (check-= (visual-rotation oriented-horizontal) 0 1e-12)
  (check-equal? (visual-position oriented-vertical)
                (vec2 3 1))
  (check-= (visual-rotation oriented-vertical) (/ pi 2) 1e-12)

  ;; A rotation offset is additive after tangent alignment.
  (define offset-orientation-scene
    (scene-play
     (scene-add (make-scene) marker)
     (orient-along-path marker
                        unequal-route
                        #:rotation-offset (/ pi 4))
     #:duration 7))
  (check-=
   (visual-rotation
    (scene-state-ref (scene-sample offset-orientation-scene 4) 'marker))
   (* 3/4 pi)
   1e-12)

  ;; Reverse path orientation points along actual motion rather than the stored
  ;; path direction.
  (define reverse-oriented-scene
    (scene-play
     (scene-add (make-scene) reverse-marker)
     (move-along-path reverse-marker unequal-route #:start 1 #:end 0)
     (orient-along-path reverse-marker unequal-route #:start 1 #:end 0)
     #:duration 7))
  (check-=
   (visual-rotation
    (scene-state-ref (scene-sample reverse-oriented-scene 2)
                     'reverse-marker))
   (- (/ pi 2))
   1e-12)

  ;; Path orientation owns only the rotation component. It composes with path
  ;; translation but conflicts with another same-target rotation request.
  (check-not-exn
   (lambda ()
     (scene-play
      (scene-add (make-scene) marker)
      (move-along-path marker unequal-route)
      (orient-along-path marker unequal-route))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) marker)
      (orient-along-path marker unequal-route)
      (rotate-to marker 0))))

  ; transformed-route : path-visual?
  ;;   Rotates a local horizontal path into the positive world y direction.
  (define transformed-route
    (make-path-visual
     (polyline-path (list origin (vec2 4 0)))
     #:id 'transformed-route
     #:center (vec2 10 5)
     #:rotation (/ pi 2)
     #:stroke "navy"))
  (define transformed-marker
    (rectangle #:id 'transformed-marker
               #:center (vec2 10 5)
               #:width 1
               #:height 1/2))
  (define transformed-scene
    (scene-play
     (scene-add (make-scene)
                transformed-route
                transformed-marker)
     (move-along-path transformed-marker transformed-route)
     (orient-along-path transformed-marker transformed-route)
     #:duration 2))
  (define transformed-mid
    (scene-state-ref (scene-sample transformed-scene 1)
                     'transformed-marker))
  (check-= (vec2-x (visual-position transformed-mid)) 10 1e-12)
  (check-= (vec2-y (visual-position transformed-mid)) 7 1e-12)
  (check-= (visual-rotation transformed-mid) (/ pi 2) 1e-12)

  ;; camera-follow tracks the actual normal-offset target position because it
  ;; samples the composed Visual state rather than the underlying route point.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center (vec2 0 1)))
  (define followed-marker
    (rectangle #:id 'followed-marker
               #:center (vec2 0 1)
               #:width 1
               #:height 1/2))
  (define followed-offset-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera) followed-marker)
     (move-along-path followed-marker
                      (polyline-path (list origin (vec2 4 0)))
                      #:normal-offset 1)
     (camera-follow followed-marker)
     #:duration 2))
  (define followed-mid-marker
    (scene-state-ref (scene-sample followed-offset-scene 1)
                     'followed-marker))
  (define followed-mid-camera
    (scene-camera-at followed-offset-scene 1))
  (check-equal? (visual-position followed-mid-marker)
                (vec2 2 1))
  (check-equal? (camera-center followed-mid-camera)
                (vec2 2 1)))
