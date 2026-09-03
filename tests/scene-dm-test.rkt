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

  ;; The results are represented as non-overlapping polygon partitions, so the
  ;; sum of absolute contour areas gives the filled area for these test cases.
  (define (subpath-area subpath)
    (define points (path-subpath-points subpath))
    (/ (for/sum ([point (in-list points)]
                 [next (in-list (append (cdr points) (list (car points))))])
         (- (* (vec2-x point) (vec2-y next))
            (* (vec2-y point) (vec2-x next))))
       2))
  (define (geometry-area geometry)
    (for/sum ([subpath (in-list (path-geometry-subpaths geometry))])
      (abs (subpath-area subpath))))

  (define overlap (path-intersection left right))
  (check-equal? (geometry-area overlap) 8)
  (check-equal? (length (path-geometry-subpaths overlap)) 1)

  (check-equal? (geometry-area (path-difference left right)) 8)
  (check-equal? (geometry-area (cutout left right)) 8)
  (check-equal? (geometry-area (path-union left right)) 24)
  (check-equal? (geometry-area (path-xor left right)) 16)

  ;; Containment produces a genuine empty intersection of the cutout pieces,
  ;; not a degenerate contour that the Pict path renderer might stroke.
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

  ;; The first API release rejects unsupported topology clearly.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-union (polyline-path (list (vec2 0 0) (vec2 1 0)))
                           right)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-union
                (polygon-path
                 (list (vec2 0 0) (vec2 2 0) (vec2 1 1) (vec2 2 2)
                       (vec2 0 2)))
                right)))
  (check-exn exn:fail:contract?
             (lambda () (path-union left right #:curve-samples 0))))
