#lang racket/base

;;;
;;; SCENE-3D-A Bounds and Intersection Tests
;;;

(require rackunit
         "../3d.rkt")

(define (check-vec3= actual expected [tolerance 1e-10])
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  (define bounds
    (aabb3-from-points (list (vec3 -1 -2 -3) (vec3 4 5 6))))
  (check-equal? (aabb3-center bounds) (vec3 3/2 3/2 3/2))
  (check-equal? (aabb3-size bounds) (vec3 5 7 9))
  (check-true (aabb3-contains? bounds origin3))
  (check-false (aabb3-contains? bounds (vec3 5 0 0)))
  (check-true (aabb3-empty? aabb3-empty))
  (check-equal? (aabb3-union aabb3-empty bounds) bounds)
  (check-equal?
   (aabb3-transform
    (aabb3 (vec3 -1 -1 -1) (vec3 1 1 1))
    (affine3 (linear3 2 0 0 0 3 0 0 0 4) (vec3 1 2 3)))
   (aabb3 (vec3 -1 -1 -1) (vec3 3 5 7)))
  (define ray (ray3 (vec3 -3 0 0) x-axis3))
  (define plane-hit
    (ray3-intersect-plane ray (plane3 (vec3 0 0 0) x-axis3)))
  (check-true (ray3-plane-hit? plane-hit))
  (check-= (ray3-plane-hit-distance plane-hit) 3 1e-10)
  (check-vec3= (ray3-plane-hit-point plane-hit) origin3)
  (define box-hit
    (ray3-intersect-aabb ray (aabb3 (vec3 -1 -1 -1) (vec3 1 1 1))))
  (check-true (ray3-aabb-hit? box-hit))
  (check-= (ray3-aabb-hit-entry box-hit) 2 1e-10)
  (check-= (ray3-aabb-hit-exit box-hit) 4 1e-10)
  (check-false
   (ray3-intersect-plane ray (plane3 (vec3 0 0 0) y-axis3)))
  (check-false
   (ray3-intersect-aabb (ray3 (vec3 -3 3 0) x-axis3)
                        (aabb3 (vec3 -1 -1 -1) (vec3 1 1 1))))
  (check-exn exn:fail? (lambda () (ray3 origin3 origin3)))
  (check-exn exn:fail:contract? (lambda () (plane3 origin3 +nan.0))))
