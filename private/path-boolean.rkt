#lang racket/base

;;;
;;; SCENE-DM: Boolean Path Geometry
;;;

;; This module deliberately starts with a useful, predictable subset of planar
;; Boolean geometry.  Each operand is one simple convex closed contour.  Cubic
;; contours are sampled into a convex polygon before clipping.  The result is
;; an ordinary path-geometry value, so it remains renderer-independent and can
;; be styled, morphed, or placed in a path-visual by the existing API.
;;
;; Difference-like operations return a non-overlapping partition rather than
;; reconstructing a single outer contour with holes.  That gives correct
;; odd-even fill semantics, including cutouts, while making the first release
;; small and explicit about the unsupported general-polygon cases.

(require "geometry.rkt"
         "path-geometry.rkt")

(provide path-union
         path-intersection
         path-difference
         path-xor
         cutout)


;;;
;;; Public Operations
;;;

;; path-union : path-geometry? path-geometry?
;;              [#:curve-samples exact-positive-integer?] -> path-geometry?
;; Returns the filled union of two simple convex closed contours.  Cubic
;; segments are replaced by `curve-samples` straight pieces before clipping.
(define (path-union first second #:curve-samples [curve-samples 16])
  (define-values (first-polygon second-polygon)
    (boolean-operands 'path-union first second curve-samples))
  ;; A union is a disjoint partition of the first operand and the part of the
  ;; second operand not already covered by it.
  (polygons->geometry
   (append (list first-polygon)
           (convex-difference second-polygon first-polygon))))

;; path-intersection : path-geometry? path-geometry?
;;                     [#:curve-samples exact-positive-integer?]
;;                     -> path-geometry?
;; Returns the filled intersection of two simple convex closed contours.
(define (path-intersection first second #:curve-samples [curve-samples 16])
  (define-values (first-polygon second-polygon)
    (boolean-operands 'path-intersection first second curve-samples))
  (polygons->geometry
   (list (convex-intersection first-polygon second-polygon))))

;; path-difference : path-geometry? path-geometry?
;;                   [#:curve-samples exact-positive-integer?]
;;                   -> path-geometry?
;; Returns the part of `first` not covered by `second`.
(define (path-difference first second #:curve-samples [curve-samples 16])
  (define-values (first-polygon second-polygon)
    (boolean-operands 'path-difference first second curve-samples))
  (polygons->geometry
   (convex-difference first-polygon second-polygon)))

;; path-xor : path-geometry? path-geometry?
;;            [#:curve-samples exact-positive-integer?] -> path-geometry?
;; Returns the part covered by exactly one of the two operands.
(define (path-xor first second #:curve-samples [curve-samples 16])
  (define-values (first-polygon second-polygon)
    (boolean-operands 'path-xor first second curve-samples))
  (polygons->geometry
   (append (convex-difference first-polygon second-polygon)
           (convex-difference second-polygon first-polygon))))

;; cutout : path-geometry? path-geometry?
;;          [#:curve-samples exact-positive-integer?] -> path-geometry?
;; A readable alias for `path-difference`, intended for a filled outer shape
;; and a shape removed from it.
(define (cutout outer inner #:curve-samples [curve-samples 16])
  (path-difference outer inner #:curve-samples curve-samples))


;;;
;;; Operand Preparation
;;;

(define numerical-epsilon 1e-10)

(define (boolean-operands who first second curve-samples)
  (check-path-geometry who "first" first)
  (check-path-geometry who "second" second)
  (check-curve-samples who curve-samples)
  (values (geometry->convex-polygon who "first" first curve-samples)
          (geometry->convex-polygon who "second" second curve-samples)))

(define (check-path-geometry who field value)
  (unless (path-geometry? value)
    (raise-arguments-error who "expected path geometry"
                           field value)))

(define (check-curve-samples who value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-arguments-error who
                           "curve-samples must be an exact positive integer"
                           "curve-samples" value)))

;; `geometry->convex-polygon` turns one closed path into a CCW polygon.  This
;; is intentionally a strict boundary: compound paths, open paths, concave
;; contours, and self intersections will be supported by a later general
;; clipping engine rather than given surprising partial semantics here.
(define (geometry->convex-polygon who field geometry curve-samples)
  (define subpaths
    (path-geometry-subpaths geometry))
  (unless (= (length subpaths) 1)
    (raise-arguments-error
     who
     "each operand must contain exactly one simple convex closed subpath"
     field geometry))
  (define subpath
    (car subpaths))
  (unless (path-subpath-closed? subpath)
    (raise-arguments-error who
                           "each operand must be a closed path"
                           field geometry))
  (define polygon
    (normalize-polygon
     (subpath->sampled-points subpath curve-samples)))
  (unless (polygon-has-area? polygon)
    (raise-arguments-error who
                           "each operand must enclose a nonzero area"
                           field geometry))
  (unless (convex-polygon? polygon)
    (raise-arguments-error
     who
     "each operand must be a simple convex contour after cubic sampling"
     field geometry))
  (if (negative? (polygon-signed-area polygon))
      (reverse polygon)
      polygon))

(define (subpath->sampled-points subpath curve-samples)
  (define-values (reverse-points _last-point)
    (for/fold ([reverse-points (list (path-subpath-start subpath))]
               [current-point (path-subpath-start subpath)])
              ([segment (in-list (path-subpath-segments subpath))])
      (define segment-points
        (cond
          [(line-path-segment? segment)
           (list (line-path-segment-end segment))]
          [(cubic-bezier-path-segment? segment)
           (for/list ([index (in-range 1 (add1 curve-samples))])
             (cubic-point current-point segment (/ index curve-samples)))]))
      (values (append (reverse segment-points) reverse-points)
              (segment-end-point segment))))
  (reverse reverse-points))

(define (segment-end-point segment)
  (cond
    [(line-path-segment? segment)
     (line-path-segment-end segment)]
    [(cubic-bezier-path-segment? segment)
     (cubic-bezier-path-segment-end segment)]))

(define (cubic-point start segment progress)
  (define complement (- 1 progress))
  (define (blend selector)
    (+ (* complement complement complement (selector start))
       (* 3 complement complement progress
          (selector (cubic-bezier-path-segment-control1 segment)))
       (* 3 complement progress progress
          (selector (cubic-bezier-path-segment-control2 segment)))
       (* progress progress progress
          (selector (cubic-bezier-path-segment-end segment)))))
  (vec2 (blend vec2-x) (blend vec2-y)))


;;;
;;; Convex Polygon Clipping
;;;

;; The following is Sutherland-Hodgman clipping.  A counter-clockwise clip
;; contour has its interior on the left of every directed edge.

(define (convex-intersection subject clip)
  (for/fold ([result subject])
            ([edge-start (in-list clip)]
             [edge-end (in-list (polygon-next-points clip))])
    (if (null? result)
        '()
        (clip-polygon result edge-start edge-end #t))))

;; A convex subtraction is built by partitioning the subject at each clip
;; half-plane.  The pieces outside at any step already belong to the answer;
;; only inside pieces continue to the next edge.
(define (convex-difference subject clip)
  (define-values (_inside result)
    (for/fold ([inside-pieces (list subject)]
               [outside-pieces '()])
              ([edge-start (in-list clip)]
               [edge-end (in-list (polygon-next-points clip))])
      (define next-inside
        (append-map-polygons
         (lambda (polygon)
           (list (clip-polygon polygon edge-start edge-end #t)))
         inside-pieces))
      (define new-outside
        (append-map-polygons
         (lambda (polygon)
           (list (clip-polygon polygon edge-start edge-end #f)))
         inside-pieces))
      (values next-inside (append outside-pieces new-outside))))
  result)

(define (append-map-polygons map-polygon polygons)
  (apply append
         (for/list ([polygon (in-list polygons)])
           (filter polygon-has-area? (map-polygon polygon)))))

;; `keep-left?` selects the closed half-plane to preserve.  Boundary points
;; occur in both half-planes; zero-area pieces are removed before becoming path
;; contours, so touching shapes keep their stable expected result.
(define (clip-polygon polygon edge-start edge-end keep-left?)
  (cond
    [(null? polygon) '()]
    [else
     (define previous
       (last-point polygon))
     (define previous-inside?
       (edge-inside? edge-start edge-end previous keep-left?))
     (define-values (reverse-result _final-point _final-inside?)
       (for/fold ([reverse-result '()]
                  [previous previous]
                  [previous-inside? previous-inside?])
                 ([current (in-list polygon)])
         (define current-inside?
           (edge-inside? edge-start edge-end current keep-left?))
         (define additions
           (cond
             [(and previous-inside? current-inside?)
              (list current)]
             [(and previous-inside? (not current-inside?))
              (list (segment-edge-intersection previous current
                                               edge-start edge-end))]
             [(and (not previous-inside?) current-inside?)
              (list (segment-edge-intersection previous current
                                               edge-start edge-end)
                    current)]
             [else '()]))
         (values (append (reverse additions) reverse-result)
                 current
                 current-inside?)))
     (normalize-polygon (reverse reverse-result))]))

(define (edge-inside? edge-start edge-end point keep-left?)
  (define side
    (cross-product (vec2- edge-end edge-start)
                   (vec2- point edge-start)))
  (if keep-left?
      (>= side (- numerical-epsilon))
      (<= side numerical-epsilon)))

(define (segment-edge-intersection segment-start segment-end
                                   edge-start edge-end)
  (define direction
    (vec2- segment-end segment-start))
  (define edge-direction
    (vec2- edge-end edge-start))
  (define denominator
    (cross-product direction edge-direction))
  ;; A transition across a half-plane cannot be parallel in ordinary input.
  ;; For nearly coincident numeric edges, retaining the segment endpoint is
  ;; safer than manufacturing an enormous unstable coordinate.
  (if (near-zero? denominator)
      segment-end
      (vec2+ segment-start
             (vec2-scale
              (/ (cross-product (vec2- edge-start segment-start)
                                edge-direction)
                 denominator)
              direction))))


;;;
;;; Polygon and Path Helpers
;;;

(define (polygons->geometry polygons)
  (define valid-polygons
    (filter polygon-has-area? polygons))
  (path-geometry
   (for/list ([polygon (in-list valid-polygons)])
     (path-subpath
      (car polygon)
      (for/list ([point (in-list (cdr polygon))])
        (line-path-segment point))
      #t))))

(define (normalize-polygon points)
  (define without-adjacent-duplicates
    (reverse
     (for/fold ([result '()])
               ([point (in-list points)])
       (if (and (pair? result)
                (points-close? point (car result)))
           result
           (cons point result)))))
  (cond
    [(and (pair? without-adjacent-duplicates)
          (points-close? (car without-adjacent-duplicates)
                         (last-point without-adjacent-duplicates)))
     (drop-last-point without-adjacent-duplicates)]
    [else without-adjacent-duplicates]))

(define (drop-last-point points)
  (reverse (cdr (reverse points))))

(define (polygon-has-area? polygon)
  (and (>= (length polygon) 3)
       (not (near-zero? (polygon-signed-area polygon)))))

(define (polygon-signed-area polygon)
  (/ (for/sum ([point (in-list polygon)]
               [next-point (in-list (polygon-next-points polygon))])
       (- (* (vec2-x point) (vec2-y next-point))
          (* (vec2-y point) (vec2-x next-point))))
     2))

(define (polygon-next-points polygon)
  (if (null? polygon)
      '()
      (append (cdr polygon) (list (car polygon)))))

(define (convex-polygon? polygon)
  (define signs
    (filter (lambda (value) (not (near-zero? value)))
            (for/list ([previous (in-list (cons (last-point polygon)
                                                   (drop-last-point polygon)))]
                       [point (in-list polygon)]
                       [next-point (in-list (polygon-next-points polygon))])
              (cross-product (vec2- point previous)
                             (vec2- next-point point)))))
  (and (pair? signs)
       (or (andmap positive? signs)
           (andmap negative? signs))))

(define (points-close? first second)
  (and (near-zero? (- (vec2-x first) (vec2-x second)))
       (near-zero? (- (vec2-y first) (vec2-y second)))))

(define (near-zero? value)
  (<= (abs value) numerical-epsilon))

(define (cross-product first second)
  (- (* (vec2-x first) (vec2-y second))
     (* (vec2-y first) (vec2-x second))))

(define (last-point points)
  (car (reverse points)))
