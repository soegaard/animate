#lang racket/base

;;;
;;; Deterministic 2D overlap checks for polyhedral nets
;;;

;; Flat net faces live in one 3D plane.  This module projects them into the
;; root face's orthonormal basis, triangulates every simple polygon in stable
;; ear order, and sums pairwise convex intersection areas.  That covers both
;; convex and concave faces without treating a shared hinge boundary as an
;; overlap.

(require racket/list
         "vec3.rkt")

(provide (struct-out net-overlap3d)
         net-polygons-overlaps3d)

(struct net-overlap3d (first-face second-face area boundary-crossings)
  #:transparent)

; net-polygons-overlaps3d : (vectorof (vectorof vec3?)) vec3? vec3? vec3?
;                           [#:tolerance nonnegative-real?]
;                           -> (immutable-vectorof net-overlap3d?)
;; Computes every positive-area overlap in stable face-index order.  `origin`,
;; `basis-e`, and `basis-f` define the common root-plane coordinates.
(define (net-polygons-overlaps3d polygons origin basis-e basis-f
                                 #:tolerance [tolerance 1e-9])
  (unless (vector? polygons)
    (raise-argument-error 'net-polygons-overlaps3d "vector?" polygons))
  (for ([point (in-list (list origin basis-e basis-f))])
    (unless (vec3? point)
      (raise-argument-error 'net-polygons-overlaps3d "vec3?" point)))
  (unless (and (real? tolerance) (>= tolerance 0))
    (raise-argument-error 'net-polygons-overlaps3d "nonnegative real?" tolerance))
  (define projected
    (for/vector ([polygon (in-vector polygons)])
      (unless (vector? polygon)
        (raise-argument-error 'net-polygons-overlaps3d "vector of polygon vectors" polygons))
      (for/list ([point (in-vector polygon)])
        (unless (vec3? point)
          (raise-argument-error 'net-polygons-overlaps3d "vector of vec3? polygons" polygons))
        (define offset (vec3- point origin))
        (vector (vec3-dot offset basis-e) (vec3-dot offset basis-f)))))
  (vector->immutable-vector
   (list->vector
    (for*/fold ([result '()]) ([first-face (in-range (vector-length projected))]
                                [second-face (in-range (add1 first-face)
                                                       (vector-length projected))])
      (define first-polygon (vector-ref projected first-face))
      (define second-polygon (vector-ref projected second-face))
      (define area (polygon-overlap-area first-polygon second-polygon tolerance))
      (if (> area tolerance)
          (append result
                  (list (net-overlap3d first-face second-face area
                                       (boundary-crossing-count first-polygon
                                                                second-polygon tolerance))))
          result)))))


;;;
;;; Polygon intersection area
;;;

(define (polygon-overlap-area first-polygon second-polygon tolerance)
  (for*/sum ([first-triangle (in-list (triangulate-simple first-polygon tolerance))]
             [second-triangle (in-list (triangulate-simple second-polygon tolerance))])
    (define clipped
      (clip-convex-polygon first-triangle second-triangle tolerance))
    (if (< (length clipped) 3)
        0
        (abs (polygon-signed-area clipped)))))

;; Ear clipping preserves authored boundary order.  It supports concave simple
;; polygons and removes redundant collinear vertices first; a malformed
;; self-intersecting face is rejected instead of silently fanning it into a
;; different shape.
(define (triangulate-simple polygon tolerance)
  (define normalized (remove-collinear (remove-adjacent-duplicates polygon tolerance)
                                       tolerance))
  (cond [(< (length normalized) 3) '()]
        [(<= (abs (polygon-signed-area normalized)) tolerance)
         '()]
        [else
         (define counterclockwise
           (if (negative? (polygon-signed-area normalized))
               (reverse normalized)
               normalized))
         (ear-clip counterclockwise tolerance)]))

(define (ear-clip points tolerance)
  (let loop ([remaining points] [triangles '()])
    (cond [(= (length remaining) 3) (reverse (cons remaining triangles))]
          [else
           (define ear-index
             (for/first ([index (in-range (length remaining))]
                         #:when (ear? remaining index tolerance))
               index))
           (unless ear-index
             (raise-arguments-error
              'net-polygons-overlaps3d
              "a simple polygonal net face with a deterministic ear decomposition"
              "polygon" points))
           (define triangle (cyclic-triple remaining ear-index))
           (loop (append (take remaining ear-index)
                         (drop remaining (add1 ear-index)))
                 (cons triangle triangles))])))

(define (ear? points index tolerance)
  (define triangle (cyclic-triple points index))
  (and (> (cross2 (vector-sub (second triangle) (first triangle))
                  (vector-sub (third triangle) (second triangle)))
          tolerance)
       (for/and ([point (in-list points)]
                 #:unless (or (equal? point (first triangle))
                              (equal? point (second triangle))
                              (equal? point (third triangle))))
         (not (point-in-triangle? point triangle tolerance)))))

(define (cyclic-triple points index)
  (define count (length points))
  (list (list-ref points (modulo (sub1 index) count))
        (list-ref points index)
        (list-ref points (modulo (add1 index) count))))

;; Sutherland--Hodgman clipping against a counter-clockwise convex triangle.
(define (clip-convex-polygon subject clip-triangle tolerance)
  (for/fold ([output subject]) ([first (in-list clip-triangle)]
                               [second (in-list (append (cdr clip-triangle)
                                                        (list (car clip-triangle))))])
    (clip-against-edge output first second tolerance)))

(define (clip-against-edge subject first second tolerance)
  (cond [(null? subject) '()]
        [else
         (define previous (last subject))
         (define previous-inside? (left-of-edge? previous first second tolerance))
         (let loop ([remaining subject]
                    [before previous]
                    [before-inside? previous-inside?]
                    [out '()])
           (cond [(null? remaining) (reverse out)]
                 [else
                  (define current (car remaining))
                  (define current-inside? (left-of-edge? current first second tolerance))
                  (define next-out
                    (cond [(and before-inside? current-inside?)
                           (cons current out)]
                          [(and before-inside? (not current-inside?))
                           (cons (line-intersection before current first second) out)]
                          [(and (not before-inside?) current-inside?)
                           (cons current
                                 (cons (line-intersection before current first second)
                                       out))]
                          [else out]))
                  (loop (cdr remaining) current current-inside? next-out)]))]))

(define (left-of-edge? point first second tolerance)
  (>= (cross2 (vector-sub second first) (vector-sub point first)) (- tolerance)))

(define (line-intersection first-a second-a first-b second-b)
  (define direction-a (vector-sub second-a first-a))
  (define direction-b (vector-sub second-b first-b))
  (define denominator (cross2 direction-a direction-b))
  (cond [(zero? denominator) first-a]
        [else
         (define progress
           (/ (cross2 (vector-sub first-b first-a) direction-b) denominator))
         (vector (+ (vector-ref first-a 0) (* progress (vector-ref direction-a 0)))
                 (+ (vector-ref first-a 1) (* progress (vector-ref direction-a 1))))]))


;;;
;;; Small 2D helpers
;;;

(define (polygon-signed-area polygon)
  (/ (for/sum ([first (in-list polygon)]
               [second (in-list (append (cdr polygon) (list (car polygon))))])
       (cross2 first second))
     2))

(define (point-in-triangle? point triangle tolerance)
  (and (left-of-edge? point (first triangle) (second triangle) tolerance)
       (left-of-edge? point (second triangle) (third triangle) tolerance)
       (left-of-edge? point (third triangle) (first triangle) tolerance)))

(define (boundary-crossing-count first-polygon second-polygon tolerance)
  (for*/sum ([first (in-list first-polygon)]
             [next-first (in-list (append (cdr first-polygon) (list (car first-polygon))))]
             [second (in-list second-polygon)]
             [next-second (in-list (append (cdr second-polygon) (list (car second-polygon))))])
    (if (proper-segment-crossing? first next-first second next-second tolerance) 1 0)))

(define (proper-segment-crossing? first-a second-a first-b second-b tolerance)
  (define a1 (cross2 (vector-sub second-a first-a) (vector-sub first-b first-a)))
  (define a2 (cross2 (vector-sub second-a first-a) (vector-sub second-b first-a)))
  (define b1 (cross2 (vector-sub second-b first-b) (vector-sub first-a first-b)))
  (define b2 (cross2 (vector-sub second-b first-b) (vector-sub second-a first-b)))
  (and (< (* a1 a2) 0) (< (* b1 b2) 0)
       (or (< a1 (- tolerance)) (> a1 tolerance))
       (or (< a2 (- tolerance)) (> a2 tolerance))
       (or (< b1 (- tolerance)) (> b1 tolerance))
       (or (< b2 (- tolerance)) (> b2 tolerance))))

(define (remove-adjacent-duplicates points tolerance)
  (for/fold ([out '()]) ([point (in-list points)])
    (if (and (pair? out) (point-close? point (last out) tolerance))
        out
        (append out (list point)))))

(define (remove-collinear points tolerance)
  (let loop ([remaining points])
    (define cleaned
      (for/list ([index (in-range (length remaining))]
                 #:unless (and (>= (length remaining) 3)
                               (<= (abs (cross2
                                         (vector-sub (list-ref remaining index)
                                                     (list-ref remaining
                                                               (modulo (sub1 index)
                                                                       (length remaining))))
                                         (vector-sub (list-ref remaining
                                                               (modulo (add1 index)
                                                                       (length remaining)))
                                                     (list-ref remaining index))))
                                    tolerance)))
        (list-ref remaining index)))
    (if (= (length cleaned) (length remaining)) cleaned (loop cleaned))))

(define (point-close? first second tolerance)
  (and (<= (abs (- (vector-ref first 0) (vector-ref second 0))) tolerance)
       (<= (abs (- (vector-ref first 1) (vector-ref second 1))) tolerance)))

(define (vector-sub first second)
  (vector (- (vector-ref first 0) (vector-ref second 0))
          (- (vector-ref first 1) (vector-ref second 1))))

(define (cross2 first second)
  (- (* (vector-ref first 0) (vector-ref second 1))
     (* (vector-ref first 1) (vector-ref second 0))))
