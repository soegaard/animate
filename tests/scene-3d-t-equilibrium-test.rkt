#lang racket/base
(require rackunit "../3d.rkt")

(module+ test
  (define seeds (explicit-seeds3d (list (vec3 -3 0 0) (vec3 2 0 0) (vec3 0 3 0))))
  (define search
    (equilibrium-points3d
     (lambda (x y z) (vec3 x y z)) seeds
     #:jacobian (lambda (x y z) identity-linear3)
     #:merge-distance 1e-5))
  (check-equal? (vector-length (equilibrium-search3d-seed-results search)) 3)
  (check-equal? (vector-length (equilibrium-search3d-roots search)) 1)
  (for ([result (in-vector (equilibrium-search3d-seed-results search))])
    (check-equal? (equilibrium-seed-result3d-status result) 'converged)
    (check-equal? (equilibrium-seed-result3d-root-index result) 0))
  (check-equal? (vector->list (equilibrium-root3d-member-seed-indices
                                (vector-ref (equilibrium-search3d-roots search) 0)))
                '(0 1 2))
  (define singular
    (equilibrium-points3d (lambda (x y z) (vec3 1 0 0))
                          (explicit-seeds3d (list (vec3 0 0 0)))
                          #:jacobian (lambda (x y z) (linear3 0 0 0 0 0 0 0 0 0))))
  (check-equal? (equilibrium-seed-result3d-status
                 (vector-ref (equilibrium-search3d-seed-results singular) 0))
                'singular-jacobian)
  (define outside
    (equilibrium-points3d (lambda (x y z) (vec3 x y z))
                          (explicit-seeds3d (list (vec3 -1 0 0)))
                          #:domain (lambda (p) (>= (vec3-x p) 0))))
  (check-equal? (equilibrium-seed-result3d-status
                 (vector-ref (equilibrium-search3d-seed-results outside) 0))
                'out-of-domain)
  (define non-finite
    (equilibrium-points3d (lambda (x y z) 'not-a-vector)
                          (explicit-seeds3d (list (vec3 0 0 0)))))
  (check-equal? (equilibrium-seed-result3d-status
                 (vector-ref (equilibrium-search3d-seed-results non-finite) 0))
                'non-finite))
