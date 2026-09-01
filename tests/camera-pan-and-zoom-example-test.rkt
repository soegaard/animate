#lang racket/base

;;;
;;; Camera Pan and Zoom Example Regression Tests
;;;

;; Checks that the example's marker follows the same sampled quadratic
;; geometry as the visible graph while the camera moves independently.


;;;
;;; Imports
;;;

(require rackunit
         "../examples/camera-pan-and-zoom.rkt"
         "../main.rkt")


(module+ test
  ; frames-per-second : exact-positive-integer?
  ;;   Gives the frame rate used by the example renderer.
  (define frames-per-second
    30)

  ; clip-duration : positive-real?
  ;;   Gives each camera-and-marker movement duration.
  (define clip-duration
    3/2)

  ; graph-value : finite-real? -> finite-real?
  ;;   Returns the quadratic used by the camera example.
  (define (graph-value x)
    (- (/ (* x x) 4)
       2))

  ; demo : scene?
  ;;   Gives the canonical camera demonstration.
  (define demo
    (make-demo-scene))

  ; coordinate-axes : axes-visual?
  ;;   Rebuilds the immutable axes snapshot used by the graph and marker routes.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -6 6 1)
          #:y-range (axis-range -4 4 1)
          #:x-length 12
          #:y-length 8
          #:stroke "navy"
          #:stroke-width 3))

  ; left-marker-route : path-geometry?
  ;;   Gives the first graph subsection traversed by the marker.
  (define left-marker-route
    (sample-function-path coordinate-axes
                          graph-value
                          #:x-min -4
                          #:x-max -2
                          #:sample-count 41
                          #:interpolation 'linear))

  ; right-marker-route : path-geometry?
  ;;   Gives the second graph subsection traversed by the marker.
  (define right-marker-route
    (sample-function-path coordinate-axes
                          graph-value
                          #:x-min -2
                          #:x-max 3
                          #:sample-count 101
                          #:interpolation 'linear))

  ; return-marker-route : path-geometry?
  ;;   Gives the final graph subsection, traversed from right to left.
  (define return-marker-route
    (sample-function-path coordinate-axes
                          graph-value
                          #:x-min 0
                          #:x-max 3
                          #:sample-count 61
                          #:interpolation 'linear))

  ; check-marker-route : nonnegative-real? path-geometry? real? real? -> void?
  ;;   Checks every rendered frame of one marker traversal against its route.
  (define (check-marker-route start-time route start-progress end-progress)
    (define start-frame
      (* frames-per-second start-time))
    (define frame-count
      (* frames-per-second clip-duration))
    (for ([frame-index (in-range start-frame
                                 (add1 (+ start-frame frame-count)))])
      (define time
        (frame-index->time frame-index #:fps frames-per-second))
      (define progress
        (/ (- time start-time) clip-duration))
      (define marker
        (scene-state-ref (scene-sample demo time) 'marker))
      (check-equal?
       (visual-position marker)
       (path-geometry-point-at
        route
        (+ start-progress
           (* progress (- end-progress start-progress)))))))

  (check-marker-route 3/2 left-marker-route 0 1)
  (check-marker-route 3 right-marker-route 0 1)
  (check-marker-route 9/2 return-marker-route 1 0))
