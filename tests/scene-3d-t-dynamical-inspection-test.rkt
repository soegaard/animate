#lang racket/base
(require rackunit "../3d.rkt" "../main.rkt")
(module+ test
  (define trajectory
    (prepare-ode-trajectory3d (lambda (x y z) (vec3 1 0 0)) (vec3 0 0 0)
                              #:time-range (cons 0 1)
                              #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (check-equal? (hash-ref (trajectory-inspection3d trajectory) 'kind) 'trajectory)
  (define trajectory-pick
    (trajectory-pick-inspection3d trajectory (vec3 3/10 1/5 0) #:samples 11))
  (check-equal? (hash-ref trajectory-pick 'kind) 'trajectory-pick)
  (check-= (hash-ref trajectory-pick 'interpolated-time) 3/10 1e-9)
  (check-equal? (hash-ref trajectory-pick 'field-derivative) x-axis3)
  (check-= (hash-ref trajectory-pick 'arc-length-position) 3/10 1e-9)
  (define phase (parameter 'phase 0))
  (define view
    (view3d (list (flow-particle3d trajectory phase #:id 'particle))
            #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 2 2 5)
                                           #:look-at origin3)))
  (define attached-reports (view3d-dynamical-inspections3d view))
  (check-equal? (length attached-reports) 1)
  (check-equal? (hash-ref (car attached-reports) 'path) '(world particle))
  (define attached-trajectory (hash-ref (car attached-reports) 'report))
  (check-equal? (hash-ref attached-trajectory 'accepted-steps) 10)
  (check-equal? (hash-ref attached-trajectory 'rejected-steps) 0)
  (check-equal? (hash-ref attached-trajectory 'event-count) 0)
  (check-equal? (hash-ref attached-trajectory 'termination-reason) 'time-range)
  (define map (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0))
                                  (explicit-seeds3d (list (vec3 0 0 0)))))
  (check-equal? (hash-ref (flow-map-inspection3d map 0) 'source) (vec3 0 0 0))
  (define linear (linearize3d (lambda (x y z) (vec3 x y z)) (vec3 0 0 0)
                              #:jacobian (lambda (x y z) (linear3 1 0 0 0 2 0 0 0 3))))
  (check-equal? (hash-ref (linearization-inspection3d linear) 'classification) 'source))
