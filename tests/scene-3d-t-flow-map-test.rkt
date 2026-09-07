#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
  (define seeds (explicit-seeds3d (list (vec3 0 0 0) (vec3 1 2 3))))
  (define map
    (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0)) seeds
                        #:start-time 0 #:end-time 2
                        #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (check-equal? (flow-map3d-ref map 0) (vec3 2 0 0))
  (check-equal? (flow-map3d-ref map 1) (vec3 3 2 3))
  (check-equal? (flow-map3d-displacement map 1) (vec3 2 0 0))
  (check-equal? (vector-length (flow-map3d-pairs map)) 2)
  (define bounded (trajectory-termination3d #:time-limit 1/2))
  (define partial
    (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0)) seeds
                        #:start-time 0 #:end-time 2 #:termination bounded))
  (check-false (flow-map3d-ref partial 0))
  (check-equal? (hash-ref (prepared-flow-map3d-diagnostics partial) 'missing-endpoint-count) 2)
  (define use-point
    (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0)) seeds
                        #:start-time 0 #:end-time 2 #:termination bounded
                        #:on-termination 'use-termination-point))
  (check-equal? (flow-map3d-ref use-point 0) (vec3 1/2 0 0))
  (check-equal? (hash-ref (prepared-flow-map3d-diagnostics map) 'cacheability)
                'memory-only)
  (define keyed
    (prepare-flow-map3d (ode-field3d (lambda (x y z) (vec3 1 0 0)) #:cache-key 'constant)
                        seeds #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (check-equal? (hash-ref (prepared-flow-map3d-diagnostics keyed) 'cacheability)
                'persistent-candidate)
  (check-true (pair? (hash-ref (prepared-flow-map3d-diagnostics keyed) 'preparation-key)))
  (define grid-map
    (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0))
                        (grid-seeds3d #:counts '(2 2 2))
                        #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (check-true (group3d? (flow-map-grid3d grid-map #:id 'grid)))
  (define volume-cell
    (flow-volume-cell3d grid-map 0 #:id 'unit-cell
                        #:material (material3d #:color "gold" #:shading 'unlit)))
  (check-true (mesh3d? volume-cell))
  (check-equal? (material3d-color (mesh3d-material volume-cell))
                (material3d-color (material3d #:color "gold" #:shading 'unlit)))
  (check-equal? (mesh3d-vertices volume-cell)
                (vector (vec3 0 -1 -1) (vec3 2 -1 -1)
                        (vec3 0 1 -1) (vec3 2 1 -1)
                        (vec3 0 -1 1) (vec3 2 -1 1)
                        (vec3 0 1 1) (vec3 2 1 1)))
  (check-equal? (vector-length (mesh3d-triangles volume-cell)) 12)
  (check-equal? (flow-map3d-local-jacobian grid-map 0) identity-linear3)
  (check-equal? (flow-map3d-volume-factor grid-map 0) 1)
  (check-exn exn:fail:contract? (lambda () (flow-volume-cell3d grid-map 1)))
  (check-exn exn:fail:contract? (lambda () (flow-map-grid3d map))))
