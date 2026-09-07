#lang racket/base

;;; SCENE-3D-T4: immutable deterministic three-dimensional seed sets.

(require rackunit
         "../3d.rkt")

(module+ test
  ;; Explicit sets retain declaration order and immutable vector storage.  A
  ;; duplicate is meaningful author input rather than a hidden normalization.
  (define explicit
    (explicit-seeds3d (list (vec3 2 0 0) origin3 (vec3 2 0 0))))
  (check-equal? (seed-set3d-kind explicit) 'explicit)
  (check-equal? (seed-set3d-points explicit)
                (vector-immutable (vec3 2 0 0) origin3 (vec3 2 0 0)))
  (check-equal? (seed-set3d-count explicit) 3)
  (check-true (immutable? (seed-set3d-points explicit)))
  (check-true (hash-ref (seed-set3d-diagnostics explicit) 'duplicate-points?))

  ;; Regular grids include endpoints, use centred singleton axes, and expose a
  ;; declared nesting order rather than hash or scheduler order.
  (define grid
    (grid-seeds3d #:x-range (list 0 2) #:y-range (list 10 12)
                  #:z-range (list -1 1) #:counts (list 2 2 2) #:order 'xyz))
  (check-equal? (seed-set3d-points grid)
                (vector-immutable (vec3 0 10 -1) (vec3 0 10 1)
                                  (vec3 0 12 -1) (vec3 0 12 1)
                                  (vec3 2 10 -1) (vec3 2 10 1)
                                  (vec3 2 12 -1) (vec3 2 12 1)))
  (check-equal?
   (seed-set3d-points
    (grid-seeds3d #:x-range (list 0 2) #:y-range (list 10 12)
                  #:z-range (list -1 1) #:counts (list 2 2 2) #:order 'zyx))
   (vector-immutable (vec3 0 10 -1) (vec3 2 10 -1)
                     (vec3 0 12 -1) (vec3 2 12 -1)
                     (vec3 0 10 1) (vec3 2 10 1)
                     (vec3 0 12 1) (vec3 2 12 1)))
  (check-equal?
   (seed-set3d-points
    (grid-seeds3d #:x-range (list 0 2) #:y-range (list 0 0)
                  #:z-range (list 0 0) #:counts (list 1 1 1)))
   (vector-immutable (vec3 1 0 0)))

  ;; Plane coordinates use the deterministic basis associated with the plane.
  (define plane-set
    (plane-seeds3d (plane3 origin3 z-axis3)
                   #:u-range (list -1 1) #:v-range (list -2 2)
                   #:counts (list 2 2)))
  (check-equal? (seed-set3d-count plane-set) 4)
  (for ([point (in-vector (seed-set3d-points plane-set))])
    (check-equal? (vec3-z point) 0))

  ;; Curves distinguish their stored-sample parameter spacing from arc-length
  ;; spacing.  This deliberately uneven curve has a recognizably different
  ;; middle seed in the two modes.
  (define uneven-curve
    (polyline3d (list origin3 (vec3 1 0 0) (vec3 11 0 0)) #:id 'uneven))
  (check-equal?
   (seed-set3d-points (curve-seeds3d uneven-curve #:count 3 #:spacing 'parameter))
   (vector-immutable origin3 (vec3 1 0 0) (vec3 11 0 0)))
  (check-equal?
   (seed-set3d-points (curve-seeds3d uneven-curve #:count 3 #:spacing 'arc-length))
   (vector-immutable origin3 (vec3 11/2 0 0) (vec3 11 0 0)))

  ;; Parametric surface seeds are generated in u-major order and any retained
  ;; domain predicate is obeyed before an evaluator is called for the result.
  (define square
    (parametric-surface3d (lambda (u v) (vec3 u v 0))
                          #:u-range (list 0 1) #:v-range (list 0 1)
                          #:resolution (list 2 2) #:id 'square))
  (check-equal?
   (seed-set3d-points (surface-seeds3d square #:u-count 2 #:v-count 2))
   (vector-immutable (vec3 0 0 0) (vec3 0 1 0)
                     (vec3 1 0 0) (vec3 1 1 0)))

  ;; Fibonacci points remain exactly on the authored sphere.
  (define sphere (sphere-seeds3d (vec3 1 -2 3) 2 #:count 7))
  (check-equal? (seed-set3d-count sphere) 7)
  (for ([point (in-vector (seed-set3d-points sphere))])
    (check-= (vec3-distance point (vec3 1 -2 3)) 2 1e-10))

  ;; Poisson construction is repeatable, has a local random source, respects
  ;; both the box and the minimum distance, and retains acceptance order.
  (define poisson-bounds (aabb3 (vec3 -2 -2 -2) (vec3 2 2 2)))
  (random-seed 77)
  (define first-poisson
    (poisson-seeds3d poisson-bounds #:minimum-distance 3/4
                     #:count-limit 12 #:seed 42))
  (random-seed 901)
  (void (random 1000))
  (define second-poisson
    (poisson-seeds3d poisson-bounds #:minimum-distance 3/4
                     #:count-limit 12 #:seed 42))
  (check-equal? (seed-set3d-points first-poisson)
                (seed-set3d-points second-poisson))
  (check-true (<= (seed-set3d-count first-poisson) 12))
  (for ([point (in-vector (seed-set3d-points first-poisson))])
    (check-true (aabb3-contains? poisson-bounds point)))
  (define poisson-points (seed-set3d-points first-poisson))
  (for* ([first-index (in-range (vector-length poisson-points))]
         [second-index (in-range (add1 first-index) (vector-length poisson-points))])
    (check-true (>= (vec3-distance (vector-ref poisson-points first-index)
                                    (vector-ref poisson-points second-index))
                      3/4))))
