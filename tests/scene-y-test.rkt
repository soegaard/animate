#lang racket/base

;;;
;;; SCENE-Y Path-Following Model Tests
;;;

;; Tests total-arc-length point sampling, continuous path-motion requests,
;; transformed path Visual routes, reverse traversal, component conflicts, and
;; exact camera following of curved or piecewise target motion.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/camera-animation.rkt"
         "../private/camera.rkt"
         "../private/frame-space.rkt"
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

  ;; Point lookup uses total arc length rather than segment index.
  (check-equal? (path-geometry-length unequal-route) 7)
  (check-equal? (path-geometry-point-at unequal-route 0)
                origin)
  (check-equal? (path-geometry-point-at unequal-route 3/7)
                (vec2 3 0))
  (check-equal? (path-geometry-point-at unequal-route 1/2)
                (vec2 3 1/2))
  (check-equal? (path-geometry-point-at unequal-route 1)
                (vec2 3 4))

  ; straight-cubic : path-geometry?
  ;;   Gives a geometrically straight cubic whose parameterization is linear.
  (define straight-cubic
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       (vec2 1 0)
       (vec2 2 0)
       (vec2 3 0)))))

  ;; Cubic lookup uses the same deterministic arc-length table as extraction.
  (check-equal? (path-geometry-point-at straight-cubic 1/2)
                (vec2 3/2 0))

  ; curved-cubic : path-geometry?
  ;;   Gives a symmetric genuinely curved cubic with a known half-length point.
  (define curved-cubic
    (cubic-bezier-path
     (vec2 -1 0)
     (list
      (cubic-bezier-path-segment
       (vec2 -1 1)
       (vec2 1 1)
       (vec2 1 0)))))
  (define curved-midpoint
    (path-geometry-point-at curved-cubic 1/2))
  (check-= (vec2-x curved-midpoint) 0 1e-10)
  (check-= (vec2-y curved-midpoint) 3/4 1e-10)

  ; closed-route : path-geometry?
  ;;   Gives one closed square whose final traversal edge returns to the start.
  (define closed-route
    (polygon-path
     (list origin
           (vec2 2 0)
           (vec2 2 2)
           (vec2 0 2))))

  ;; Closed-path traversal includes the implicit closing edge.
  (check-equal? (path-geometry-point-at closed-route 1)
                origin)

  ; disconnected-route : path-geometry?
  ;;   Gives two positive-length subpaths separated by a spatial gap.
  (define disconnected-route
    (path-geometry
     (list
      (path-subpath origin
                    (list (line-path-segment (vec2 1 0)))
                    #f)
      (path-subpath (vec2 3 0)
                    (list (line-path-segment (vec2 4 0)))
                    #f))))

  ;; General point lookup preserves significant traversal order at a boundary.
  (check-equal? (path-geometry-point-at disconnected-route 1/2)
                (vec2 1 0))

  ; zero-route : path-geometry?
  ;;   Gives a path with semantic geometry but no positive arc length.
  (define zero-route
    (path-geometry
     (list
      (path-subpath origin
                    (list (line-path-segment origin))
                    #f))))

  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-point-at empty-path-geometry 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-point-at zero-route 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-point-at unequal-route -1/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-point-at unequal-route 11/10)))

  ; marker : circle-visual?
  ;;   Gives the ordinary translation target used by path-motion tests.
  (define marker
    (circle #:id 'marker
            #:center origin
            #:radius 1/4
            #:fill "crimson"))

  ;; Public request construction accepts semantic geometry and reversible ranges.
  (check-true
   (move-along-path-request?
    (move-along-path marker unequal-route)))
  (check-true
   (move-along-path-request?
    (move-along-path 'marker unequal-route #:start 1 #:end 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (move-along-path marker 42)))
  (check-exn exn:fail:contract?
             (lambda ()
               (move-along-path marker unequal-route #:start -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (move-along-path marker unequal-route #:end 2)))

  ; base-scene : scene?
  ;;   Gives marker at the first point of unequal-route.
  (define base-scene
    (scene-add (make-scene)
               marker))

  ; forward-scene : scene?
  ;;   Traverses seven world units in seven seconds under linear easing.
  (define forward-scene
    (scene-play base-scene
                (move-along-path marker unequal-route)
                #:duration 7))

  ;; Linear easing gives constant speed in arc-length units.
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample forward-scene 3)
                     'marker))
   (vec2 3 0))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample forward-scene 7/2)
                     'marker))
   (vec2 3 1/2))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state forward-scene)
                     'marker))
   (vec2 3 4))

  ; reverse-marker : circle-visual?
  ;;   Gives a target beginning at the route's final point.
  (define reverse-marker
    (circle #:id 'reverse-marker
            #:center (vec2 3 4)
            #:radius 1/4))

  ; reverse-scene : scene?
  ;;   Traverses the same geometry from fraction one back to zero.
  (define reverse-scene
    (scene-play
     (scene-add (make-scene) reverse-marker)
     (move-along-path reverse-marker unequal-route #:start 1 #:end 0)
     #:duration 7))

  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample reverse-scene 4)
                     'reverse-marker))
   (vec2 3 0))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state reverse-scene)
                     'reverse-marker))
   origin)

  ; partial-marker : circle-visual?
  ;;   Begins at one interior route fraction for a partial traversal check.
  (define partial-marker
    (circle #:id 'partial-marker
            #:center (path-geometry-point-at unequal-route 1/7)
            #:radius 1/4))
  (define partial-scene
    (scene-play
     (scene-add (make-scene) partial-marker)
     (move-along-path partial-marker unequal-route #:start 1/7 #:end 4/7)
     #:duration 3))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state partial-scene)
                     'partial-marker))
   (vec2 3 1))

  ;; Path motion reserves the ordinary translation component.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (move-to marker (vec2 1 1))
                 (move-along-path marker unequal-route))))

  ;; A discontinuous geometry is useful for drawing but rejected as one motion
  ;; route so the target cannot silently teleport between subpaths.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (move-along-path marker disconnected-route))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (move-along-path marker zero-route))))

  ; transformed-route : path-visual?
  ;;   Gives an L route whose nonuniform scale changes its arc-length weighting.
  (define transformed-route
    (make-path-visual
     (polyline-path
      (list origin
            (vec2 1 0)
            (vec2 1 2)))
     #:id 'transformed-route
     #:center (vec2 10 5)
     #:scale (vec2 2 1)
     #:stroke "navy"))

  ; transformed-marker : circle-visual?
  ;;   Begins at the transformed route's world-space start point.
  (define transformed-marker
    (circle #:id 'transformed-marker
            #:center (vec2 10 5)
            #:radius 1/4))

  ;; A path Visual argument resolves by identity at clip start and applies the
  ;; route's current affine transform before arc-length measurement.
  (check-true
   (move-along-path-request?
    (move-along-path transformed-marker transformed-route)))
  (define transformed-scene
    (scene-play
     (scene-add (make-scene)
                transformed-route
                transformed-marker)
     (move-along-path transformed-marker transformed-route)
     #:duration 2))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample transformed-scene 1)
                     'transformed-marker))
   (vec2 12 5))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state transformed-scene)
                     'transformed-marker))
   (vec2 12 7))

  ;; Passing an earlier Visual value still resolves the current scene Visual by
  ;; stable identity rather than capturing a stale transform in the request.
  (define moved-route-scene
    (scene-play
     (scene-add (make-scene)
                transformed-route
                transformed-marker)
     (move-to transformed-route (vec2 20 5))
     #:duration 1))
  (define current-route-motion
    (scene-play moved-route-scene
                (move-along-path transformed-marker transformed-route)
                #:duration 1))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state current-route-motion)
                     'transformed-marker))
   (vec2 22 7))

  ;; Symbolic routes fail clearly when missing or when they identify a non-path.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (move-along-path marker 'missing-route))))
  (define not-a-route
    (circle #:id 'not-a-route #:center origin #:radius 1/2))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add base-scene not-a-route)
      (move-along-path marker 'not-a-route))))

  ; test-camera : camera?
  ;;   Gives a two-to-one camera for exact camera-follow tests.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "white"))

  ; elbow-route : path-visual?
  ;;   Gives equal-length horizontal and vertical route edges.
  (define elbow-route
    (make-path-visual
     (polyline-path
      (list origin
            (vec2 2 0)
            (vec2 2 2)))
     #:id 'elbow-route
     #:stroke "navy"))

  ; tracking-marker : circle-visual?
  ;;   Begins exactly at the elbow route's first point and camera center.
  (define tracking-marker
    (circle #:id 'tracking-marker
            #:center origin
            #:radius 1/4))

  ;; camera-follow now samples the actual Visual state. At half progress the
  ;; target is at the elbow, not halfway between route endpoints.
  (define followed-path-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera)
                elbow-route
                tracking-marker)
     (move-along-path tracking-marker elbow-route)
     (camera-follow tracking-marker)
     (camera-zoom-by 2)
     #:duration 2))
  (define followed-mid-state
    (scene-sample followed-path-scene 1))
  (define followed-mid-marker
    (scene-state-ref followed-mid-state 'tracking-marker))
  (define followed-mid-camera
    (scene-camera-at followed-path-scene 1))
  (check-equal? (visual-position followed-mid-marker)
                (vec2 2 0))
  (check-equal? (camera-center followed-mid-camera)
                (vec2 2 0))
  (check-equal? (camera-world-width followed-mid-camera)
                15)
  (define-values (marker-pixel-x marker-pixel-y)
    (camera-world->pixel followed-mid-camera
                         (visual-position followed-mid-marker)))
  (check-equal? marker-pixel-x 100)
  (check-equal? marker-pixel-y 50)

  ;; A world-space path Visual route cannot accidentally drive frame coordinates.
  (define frame-marker
    (fixed-in-frame
     (circle #:id 'frame-marker #:center origin #:radius 1/4)
     #:camera test-camera
     #:at origin))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 elbow-route
                 frame-marker)
      (move-along-path frame-marker elbow-route))))

  ;; Direct path geometry is interpreted in the target's containing coordinate
  ;; system, so frame-space path motion remains possible without mixing domains.
  (define frame-motion-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera)
                frame-marker)
     (move-along-path frame-marker
                      (polyline-path
                       (list origin (vec2 3 0))))
     #:duration 1))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state frame-motion-scene)
                     'frame-marker))
   (vec2 3 0)))
