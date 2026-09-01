#lang racket/base

;;;
;;; SCENE-AB Path Reversal and Cyclic Start Model Tests
;;;

;; Tests exact line/cubic traversal reversal, closed-loop phase changes,
;; validation, and direct reuse by the existing path animation machinery.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; check-vec2~= : vec2? vec2? nonnegative-real? -> void?
  ;;   Checks two semantic points componentwise with tolerance.
  (define (check-vec2~= actual expected tolerance)
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  ; check-opposite-vec2~= : vec2? vec2? nonnegative-real? -> void?
  ;;   Checks actual against the negation of expected.
  (define (check-opposite-vec2~= actual expected tolerance)
    (check-= (vec2-x actual) (- (vec2-x expected)) tolerance)
    (check-= (vec2-y actual) (- (vec2-y expected)) tolerance))

  ;; Open straight paths reverse their stored traversal order exactly.
  (define open-route
    (polyline-path
     (list (vec2 -3 0)
           (vec2 -1 2)
           (vec2 2 2)
           (vec2 4 -1))))
  (define reversed-open
    (path-geometry-reverse open-route))
  (check-equal?
   (path-geometry-subpath-points reversed-open)
   (list (list (vec2 4 -1)
               (vec2 2 2)
               (vec2 -1 2)
               (vec2 -3 0))))
  (check-= (path-geometry-length reversed-open)
           (path-geometry-length open-route)
           1e-12)
  (for ([fraction (in-list '(0 1/10 1/3 3/5 9/10 1))])
    (check-vec2~=
     (path-geometry-point-at reversed-open fraction)
     (path-geometry-point-at open-route (- 1 fraction))
     1e-10))
  ;; Avoid polyline corners when comparing the one-sided tangent convention.
  (for ([fraction (in-list '(1/20 1/5 1/2 4/5 19/20))])
    (check-opposite-vec2~=
     (path-geometry-tangent-at reversed-open fraction)
     (path-geometry-tangent-at open-route (- 1 fraction))
     1e-10))

  ;; Cubic reversal swaps the control points and changes the endpoint to the
  ;; original segment start.
  (define cubic-route
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       (vec2 1 3)
       (vec2 3 3)
       (vec2 4 0)))))
  (define reversed-cubic
    (path-geometry-reverse cubic-route))
  (define reversed-cubic-subpath
    (car (path-geometry-subpaths reversed-cubic)))
  (define reversed-cubic-segment
    (car (path-subpath-segments reversed-cubic-subpath)))
  (check-equal? (path-subpath-start reversed-cubic-subpath) (vec2 4 0))
  (check-true (cubic-bezier-path-segment? reversed-cubic-segment))
  (check-equal?
   (cubic-bezier-path-segment-control1 reversed-cubic-segment)
   (vec2 3 3))
  (check-equal?
   (cubic-bezier-path-segment-control2 reversed-cubic-segment)
   (vec2 1 3))
  (check-equal?
   (cubic-bezier-path-segment-end reversed-cubic-segment)
   origin)
  (for ([fraction (in-list '(0 1/8 1/3 2/3 7/8 1))])
    (check-vec2~=
     (path-geometry-point-at reversed-cubic fraction)
     (path-geometry-point-at cubic-route (- 1 fraction))
     1e-7))

  ;; Closed reversal deliberately preserves the original loop start. The old
  ;; implicit closing line is materialized when necessary so f maps to 1-f.
  (define closed-route
    (polygon-path
     (list origin
           (vec2 4 0)
           (vec2 3 3)
           (vec2 -1 2))))
  (define reversed-closed
    (path-geometry-reverse closed-route))
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths reversed-closed))))
  (check-equal?
   (path-subpath-start
    (car (path-geometry-subpaths reversed-closed)))
   origin)
  (check-= (path-geometry-length reversed-closed)
           (path-geometry-length closed-route)
           1e-12)
  (for ([fraction (in-list '(0 1/12 1/4 1/2 3/4 11/12 1))])
    (check-vec2~=
     (path-geometry-point-at reversed-closed fraction)
     (path-geometry-point-at closed-route (- 1 fraction))
     1e-10))

  ;; Cyclic start changes only the phase of one closed loop. One third of this
  ;; rectangle's perimeter lands exactly at (4, 0).
  (define rectangle-loop
    (polygon-path
     (list origin
           (vec2 4 0)
           (vec2 4 2)
           (vec2 0 2))))
  (define cycled-rectangle
    (path-geometry-cycle-start rectangle-loop 1/3))
  (check-equal?
   (path-subpath-start
    (car (path-geometry-subpaths cycled-rectangle)))
   (vec2 4 0))
  (check-= (path-geometry-length cycled-rectangle)
           (path-geometry-length rectangle-loop)
           1e-12)
  (for ([fraction (in-list '(0 1/12 1/4 1/2 3/4 11/12 1))])
    (define expected-fraction
      (let ([sum (+ 1/3 fraction)])
        (if (> sum 1) (- sum 1) sum)))
    (check-vec2~=
     (path-geometry-point-at cycled-rectangle fraction)
     (path-geometry-point-at rectangle-loop expected-fraction)
     1e-10))

  ;; Arbitrary phase values may split an edge rather than requiring a stored
  ;; vertex. On this rectangle 1/6 lies halfway along the first edge.
  (define mid-edge-cycle
    (path-geometry-cycle-start rectangle-loop 1/6))
  (check-equal?
   (path-subpath-start
    (car (path-geometry-subpaths mid-edge-cycle)))
   (vec2 2 0))
  (check-equal?
   (path-geometry-point-at mid-edge-cycle 1)
   (vec2 2 0))
  ;; Cycling one straight edge splits only that edge. Untouched rectangle
  ;; vertices remain exact, and the final straight prefix is represented by
  ;; the implicit close rather than a duplicate explicit segment.
  (check-equal?
   (path-subpath-points
    (car (path-geometry-subpaths mid-edge-cycle)))
   (list (vec2 2 0)
         (vec2 4 0)
         (vec2 4 2)
         (vec2 0 2)
         origin))

  ;; The same operation works inside cubic geometry using the deterministic
  ;; arc-length inversion already shared by point and tangent sampling.
  (define closed-cubic
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       (vec2 2 3)
       (vec2 4 3)
       (vec2 5 0)))
     #:closed? #t))
  (define closed-cubic-start
    (path-geometry-point-at closed-cubic 1/4))
  (define cycled-cubic
    (path-geometry-cycle-start closed-cubic 1/4))
  (check-vec2~=
   (path-geometry-point-at cycled-cubic 0)
   closed-cubic-start
   1e-7)
  (check-vec2~=
   (path-geometry-point-at cycled-cubic 1)
   closed-cubic-start
   1e-7)
  (check-= (path-geometry-length cycled-cubic)
           (path-geometry-length closed-cubic)
           1e-6)

  ;; Zero and one name the existing closed-loop phase exactly and preserve the
  ;; original immutable object.
  (check-eq? (path-geometry-cycle-start rectangle-loop 0) rectangle-loop)
  (check-eq? (path-geometry-cycle-start rectangle-loop 1) rectangle-loop)

  ;; Geometry operations compose directly with the existing animation API.
  ;; Reversing a closed route keeps the rider's clip-start point unchanged.
  (define rider
    (rectangle #:id 'rider
               #:center origin
               #:width 1/2
               #:height 1/4))
  (define reverse-traversal
    (scene-play
     (scene-add (make-scene) rider)
     (move-along-path rider reversed-closed)
     (orient-along-path rider reversed-closed)
     #:duration 2))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample reverse-traversal 0) 'rider))
   origin)
  (check-vec2~=
   (visual-position
    (scene-state-ref (scene-sample reverse-traversal 1) 'rider))
   (path-geometry-point-at reversed-closed 1/2)
   1e-10)

  ;; A cycled destination remains ordinary path geometry and therefore works
  ;; with the already-existing normalized morph preparation.
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph rectangle-loop cycled-rectangle))
  (check-true
   (path-geometry-morph-compatible? normalized-source normalized-destination))

  ;; Cyclic phase is intentionally defined only for one positive-length closed
  ;; subpath; open, empty/multiple, degenerate, and invalid fractions fail.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start open-route 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start empty-path-geometry 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start
                (path-geometry
                 (list (car (path-geometry-subpaths rectangle-loop))
                       (car (path-geometry-subpaths rectangle-loop))))
                1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start
                (path-geometry
                 (list (path-subpath origin '() #t)))
                1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start rectangle-loop -1/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-cycle-start rectangle-loop 11/10))))
