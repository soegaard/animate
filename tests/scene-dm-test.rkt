#lang racket/base

;;;
;;; SCENE-DM Boolean Path Geometry Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define left
    (polygon-path
     (list (vec2 0 0) (vec2 4 0) (vec2 4 4) (vec2 0 4))))
  (define right
    (polygon-path
     (list (vec2 2 0) (vec2 6 0) (vec2 6 4) (vec2 2 4))))

  ;; Results are reconstructed boundary loops. Outer loops are counterclockwise
  ;; and hole loops clockwise, so their signed sum is the filled area.
  (define (subpath-area subpath)
    (define points (path-subpath-points subpath))
    (/ (for/sum ([point (in-list points)]
                 [next (in-list (append (cdr points) (list (car points))))])
         (- (* (vec2-x point) (vec2-y next))
            (* (vec2-y point) (vec2-x next))))
       2))
  (define (geometry-area geometry)
    (abs (for/sum ([subpath (in-list (path-geometry-subpaths geometry))])
           (subpath-area subpath))))

  (define overlap (path-intersection left right))
  (check-equal? (geometry-area overlap) 8)
  (check-equal? (length (path-geometry-subpaths overlap)) 1)

  (check-equal? (geometry-area (path-difference left right)) 8)
  (check-equal? (geometry-area (cutout left right)) 8)
  (check-equal? (geometry-area (path-union left right)) 24)
  (check-equal? (geometry-area (path-xor left right)) 16)

  ;; Containment reconstructs an exterior and a reversed hole loop, avoiding
  ;; visible partition seams when the result is stroked.
  (define outer
    (polygon-path
     (list (vec2 0 0) (vec2 6 0) (vec2 6 6) (vec2 0 6))))
  (define inner
    (polygon-path
     (list (vec2 2 2) (vec2 4 2) (vec2 4 4) (vec2 2 4))))
  (define disjoint
    (polygon-path
     (list (vec2 8 0) (vec2 10 0) (vec2 10 2) (vec2 8 2))))
  (check-equal? (geometry-area (path-difference outer inner)) 32)
  (check-equal? (length (path-geometry-subpaths (path-difference outer inner))) 2)
  (check-true (path-geometry-empty? (path-intersection outer disjoint)))

  ;; Cubic path operands are sampled before clipping.  Two overlapping circles
  ;; therefore retain a single nonempty closed contour in the result.
  (define first-ellipse
    (path-visual-path
     (ellipse #:id 'first-ellipse #:center origin #:width 4 #:height 4)))
  (define second-ellipse
    (path-visual-path
     (ellipse #:id 'second-ellipse #:center (vec2 1 0) #:width 4 #:height 4)))
  (define sampled-overlap
    (path-intersection first-ellipse second-ellipse #:curve-samples 8))
  (check-equal? (length (path-geometry-subpaths sampled-overlap)) 1)
  (check-true (> (geometry-area sampled-overlap) 0))

  ;; A concave contour is triangulated internally, but reconstructs as one
  ;; exterior loop rather than showing the triangulation.
  (define concave
    (polygon-path
     (list (vec2 0 0) (vec2 4 0) (vec2 4 1) (vec2 1 1)
           (vec2 1 4) (vec2 0 4))))
  (define concave-overlap (path-intersection concave right))
  (check-equal? (geometry-area concave-overlap) 2)
  (check-equal? (length (path-geometry-subpaths concave-overlap)) 1)

  ;; Compound contours follow the renderer's odd-even filling by default.
  (define (subpath points)
    (car (path-geometry-subpaths (polygon-path points))))
  (define donut
    (path-geometry
     (list (subpath (list (vec2 0 0) (vec2 6 0) (vec2 6 6) (vec2 0 6)))
           (subpath (list (vec2 2 2) (vec2 4 2) (vec2 4 4) (vec2 2 4))))))
  (define covering-square
    (polygon-path
     (list (vec2 -1 -1) (vec2 7 -1) (vec2 7 7) (vec2 -1 7))))
  (define donut-result (path-intersection donut covering-square))
  (check-equal? (geometry-area donut-result) 32)
  (check-equal? (length (path-geometry-subpaths donut-result)) 2)

  ;; Nonzero filling instead uses contour orientation. Reversing the inner
  ;; contour turns it into a hole; keeping it CCW leaves the whole square full.
  (define nonzero-donut
    (path-geometry
     (list (subpath (list (vec2 0 0) (vec2 6 0) (vec2 6 6) (vec2 0 6)))
           (subpath (list (vec2 2 2) (vec2 2 4) (vec2 4 4) (vec2 4 2))))))
  (check-equal?
   (geometry-area
    (path-intersection nonzero-donut covering-square #:fill-rule 'nonzero))
   32)
  (check-equal?
   (geometry-area
    (path-intersection donut covering-square #:fill-rule 'nonzero))
   36)

  ;; Geometric clipping/masking are named intersection aliases; paint-aware
  ;; visual masks are a later layer on top of this deterministic geometry.
  (check-equal? (clip-to concave right) concave-overlap)
  (check-equal? (mask-with concave right) concave-overlap)

  ;; Open paths remain invalid, but proper self crossings are repaired under
  ;; the default odd-even rule by extracting their filled arrangement faces.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-union (polyline-path (list (vec2 0 0) (vec2 1 0)))
                           right)))
  (define bow-tie
    (polygon-path
     (list (vec2 0 0) (vec2 2 2) (vec2 0 2) (vec2 2 0))))
  (define repaired-bow-tie (path-union bow-tie empty-path-geometry))
  (check-equal? (geometry-area repaired-bow-tie) 2)
  (check-equal? (length (path-geometry-subpaths repaired-bow-tie)) 2)
  ;; Nonzero repair would need an arrangement carrying winding counts, rather
  ;; than the even-odd face selection used by this first repair pass.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-union
                bow-tie empty-path-geometry #:fill-rule 'nonzero)))
  (check-exn exn:fail:contract?
             (lambda () (path-union left right #:curve-samples 0))))
