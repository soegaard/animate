#lang racket/base

;; Independent seed work may use bounded worker threads, but its values,
;; diagnostics, and retained slot order must equal a serial preparation.

(require rackunit
         "../3d.rkt")

(module+ test
  (define field (ode-field3d (lambda (_x _y _z) x-axis3)
                             #:cache-key 'constant-x))
  (define seeds
    (explicit-seeds3d (list (vec3 -1 2 0) origin3 (vec3 3 -2 1))))
  (define solver (fixed-rk4-solver3d #:step-size 1/4))
  (define termination (trajectory-termination3d #:time-limit 1))
  (define samples
    (streamline-sample-policy3d #:maximum-chord-error 0
                                #:maximum-turn-angle 0
                                #:maximum-segment-length 1/4
                                #:minimum-segment-length 1/10000))

  (define serial-lines
    (prepare-streamlines3d field seeds #:solver solver #:termination termination
                           #:sample-policy samples #:parallel? #f))
  (define threaded-lines
    (prepare-streamlines3d field seeds #:solver solver #:termination termination
                           #:sample-policy samples #:parallel? #t))
  (check-equal? (prepared-streamline-set3d-streamlines threaded-lines)
                (prepared-streamline-set3d-streamlines serial-lines))
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics serial-lines))
                'serial)
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics threaded-lines))
                'threaded)

  (define serial-map
    (prepare-flow-map3d field seeds #:solver solver #:parallel? #f))
  (define threaded-map
    (prepare-flow-map3d field seeds #:solver solver #:parallel? #t))
  (check-equal? (prepared-flow-map3d-trajectories threaded-map)
                (prepared-flow-map3d-trajectories serial-map))
  (check-equal? (prepared-flow-map3d-endpoints threaded-map)
                (prepared-flow-map3d-endpoints serial-map))
  (check-equal? (hash-ref (prepared-flow-map3d-diagnostics serial-map) 'parallel-mode)
                'serial)
  (check-equal? (hash-ref (prepared-flow-map3d-diagnostics threaded-map) 'parallel-mode)
                'threaded)

  ;; A Poincare map retains every original seed slot even when its streamline
  ;; preparations run in worker threads.
  (define plane (plane3 origin3 x-axis3))
  (define serial-poincare
    (prepare-poincare-map3d field plane seeds #:solver solver
                            #:termination termination #:parallel? #f))
  (define threaded-poincare
    (prepare-poincare-map3d field plane seeds #:solver solver
                            #:termination termination #:parallel? #t))
  (check-equal? (prepared-poincare-map3d-trajectories threaded-poincare)
                (prepared-poincare-map3d-trajectories serial-poincare))
  (check-equal? (prepared-poincare-map3d-first-hits threaded-poincare)
                (prepared-poincare-map3d-first-hits serial-poincare))
  (check-equal? (hash-ref (prepared-poincare-map3d-diagnostics serial-poincare) 'parallel-mode)
                'serial)
  (check-equal? (hash-ref (prepared-poincare-map3d-diagnostics threaded-poincare) 'parallel-mode)
                'threaded))
