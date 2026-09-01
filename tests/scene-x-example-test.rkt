#lang racket/base

;;;
;;; SCENE-X Canonical Example Regression Tests
;;;

;; Checks that the fixed-overlay demonstration's marker actually traverses the
;; same sampled quadratic geometry shown by its world-space function graph.
;; SCENE-Y replaces the earlier many-clip workaround with one arc-length motion.


;;;
;;; Imports
;;;

(require rackunit
         "../examples/fixed-overlays-and-callouts.rkt"
         "../main.rkt")


(module+ test
  ; movement-start-time : nonnegative-real?
  ;;   Gives the absolute time when the marker begins traversing the graph.
  (define movement-start-time
    3/2)

  ; movement-duration : positive-real?
  ;;   Gives the duration of the marker and camera movement in the example.
  (define movement-duration
    3)

  ; graph-value : finite-real? -> finite-real?
  ;;   Returns the numeric y coordinate used by the example's quadratic.
  (define (graph-value x)
    (/ (* x x) 4))

  ; demo : scene?
  ;;   Gives the canonical fixed-overlay demonstration under regression test.
  (define demo
    (make-demo-scene))

  ; coordinate-axes : axes-visual?
  ;;   Gives the unchanged axes used to rebuild the exact marker route.
  (define coordinate-axes
    (scene-state-ref (scene-sample demo movement-start-time)
                     'coordinate-axes))

  ; marker-route : path-geometry?
  ;;   Gives the exact graph-sample subset traversed by the marker.
  (define marker-route
    (sample-function-path coordinate-axes
                          graph-value
                          #:x-min -4
                          #:x-max 4
                          #:sample-count 121
                          #:interpolation 'linear))

  ;; Every 30 fps sample during the three-second traversal lies on the same
  ;; piecewise-linear quadratic geometry that the visible graph uses there.
  (for ([frame-index (in-range 45 136)])
    (define time
      (frame-index->time frame-index #:fps 30))
    (define state
      (scene-sample demo time))
    (define marker
      (scene-state-ref state 'marker))
    (define camera
      (scene-camera-at demo time))
    (define progress
      (/ (- time movement-start-time)
         movement-duration))
    (check-equal?
     (visual-position marker)
     (path-geometry-point-at marker-route progress))
    (check-equal?
     (camera-center camera)
     (vec2-lerp origin (vec2 2 1) progress))
    (check-equal?
     (camera-world-width camera)
     (real-lerp 16 8 progress)))

  ;; One path-motion clip now replaces the previous 120 tiny move-to clips.
  (check-equal? (scene-clip-count demo) 3)

  ;; The corrected example preserves the original camera destination/duration.
  (check-equal? (scene-duration demo) 5)
  (check-equal? (camera-center (scene-current-camera demo))
                (vec2 2 1))
  (check-equal? (camera-world-width (scene-current-camera demo))
                8))
