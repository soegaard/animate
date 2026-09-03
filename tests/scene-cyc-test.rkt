#lang racket/base

;;;
;;; SCENE-CY-C Pointwise Map Tests
;;;

;; Verifies world-space nonlinear mapping, path resampling, primitive-to-path
;; conversion, and the exact start-state rule for apply-pointwise.

(require racket/list
         rackunit
         "../main.rkt")

(module+ test
  (define (square-map point)
    (define x (vec2-x point))
    (define y (vec2-y point))
    (vec2 (- (* x x) (* y y)) (* 2 x y)))

  (define horizontal
    (line (vec2 -1 1) (vec2 1 1) #:id 'horizontal #:stroke "navy"))
  (define mapped
    (scene-play
     (scene-add (make-scene) horizontal)
     (apply-pointwise 'horizontal square-map #:samples 8)
     #:duration 2))

  ;; The source value at time zero is not normalized or rebuilt.
  (check-equal? (scene-visual-at mapped 'horizontal 0) horizontal)
  (define endpoint
    (scene-visual-at mapped 'horizontal 2))
  (check-true (path-visual? endpoint))
  ;; z^2 maps the line y=1 to a parabola. Resampling creates interior points,
  ;; and the midpoint x=0 maps to (-1, 0), not a straight endpoint chord.
  (define endpoint-points
    (car (path-geometry-subpath-points (path-visual-path endpoint))))
  (check-equal? (car endpoint-points) (vec2 0 -2))
  (check-equal? (list-ref endpoint-points 4) (vec2 -1 0))
  (check-equal? (last endpoint-points) (vec2 0 2))

  ;; A semantic circle becomes a sampled path whose points are transformed in
  ;; world space, including its original translation.
  (define disc
    (circle #:id 'disc #:center (vec2 1 0) #:radius 1 #:fill #f))
  (define disc-scene
    (scene-play
     (scene-add (make-scene) disc)
     (apply-pointwise 'disc square-map #:samples 12)
     #:duration 1))
  (define mapped-disc
    (scene-visual-at disc-scene 'disc 1))
  (check-true (path-visual? mapped-disc))
  ;; The local circle point (1,0), placed at world (2,0), maps to (4,0).
  (check-equal?
   (car (car (path-geometry-subpath-points (path-visual-path mapped-disc))))
   (vec2 4 0))

  ;; A nested target is resolved into world coordinates, then rebased through
  ;; its enclosing transform. Its sibling stays untouched and its displayed
  ;; geometry still uses the requested world-space map.
  (define guide
    (line (vec2 -1 -1) (vec2 1 -1) #:id 'guide #:stroke "gray"))
  (define nested
    (scene-play
     (scene-add
      (make-scene)
      (group (list horizontal guide) #:id 'diagram #:center (vec2 2 0)))
     (apply-pointwise '(diagram horizontal) square-map #:samples 8)
     #:duration 1))
  (define rebased-curve
    (scene-visual-at nested '(diagram horizontal) 1))
  (check-true (affine-map-visual? rebased-curve))
  (define world-curve (affine-map-visual-content rebased-curve))
  (check-true (path-visual? world-curve))
  ;; The source endpoints are at world (1,1) and (3,1), so z^2 gives
  ;; (0,2) and (8,6).
  (define nested-points
    (car (path-geometry-subpath-points (path-visual-path world-curve))))
  (check-equal? (car nested-points) (vec2 0 2))
  (check-equal? (last nested-points) (vec2 8 6))
  (check-equal?
   (scene-visual-at nested '(diagram guide) 1)
   guide))
