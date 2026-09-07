#lang racket/base

(require "../geometry.rkt" "ode-flow3d.rkt" "seed-set3d.rkt" "vec3.rkt")

(provide (struct-out prepared-flow-map3d)
         prepare-flow-map3d flow-map3d-ref flow-map3d-pairs flow-map3d-displacement)

;; Endpoints are #f when a trajectory ended early under the default policy.
;; The retained trajectory and diagnostics still expose why, in the original
;; seed slot.  This makes the map a partial map rather than a hidden claim.
(struct prepared-flow-map3d (start-time end-time seeds endpoints trajectories diagnostics) #:transparent)

(define (prepare-flow-map3d field seeds
                            #:start-time [start-time 0]
                            #:end-time [end-time 1]
                            #:solver [solver #f]
                            #:termination [termination #f]
                            #:on-termination [on-termination 'absent]
                            #:parallel? [parallel? #t])
  (unless (seed-set3d? seeds) (raise-argument-error 'prepare-flow-map3d "seed-set3d?" seeds))
  (unless (and (finite-real? start-time) (finite-real? end-time) (< start-time end-time))
    (raise-argument-error 'prepare-flow-map3d "increasing finite start/end times" (list start-time end-time)))
  (unless (memq on-termination '(absent use-termination-point))
    (raise-argument-error 'prepare-flow-map3d "'absent or 'use-termination-point as #:on-termination" on-termination))
  (unless (boolean? parallel?) (raise-argument-error 'prepare-flow-map3d "boolean? as #:parallel?" parallel?))
  (define trajectories
    (vector->immutable-vector
     (list->vector
      (for/list ([seed (in-vector (seed-set3d-points seeds))])
        (prepare-ode-trajectory3d field seed #:time-range (cons start-time end-time)
                                  #:solver solver #:termination termination)))))
  (define endpoints
    (vector->immutable-vector
     (list->vector
      (for/list ([trajectory (in-vector trajectories)])
        (define actual-end (cdr (ode-trajectory3d-time-range trajectory)))
        (cond [(= actual-end end-time) (ode-trajectory3d-position trajectory actual-end)]
              [(eq? on-termination 'use-termination-point)
               (ode-trajectory3d-position trajectory actual-end)]
              [else #f])))))
  (prepared-flow-map3d
   start-time end-time seeds endpoints trajectories
   (hasheq 'seed-count (seed-set3d-count seeds)
           'endpoint-count (for/sum ([point (in-vector endpoints)]) (if point 1 0))
           'missing-endpoint-count (for/sum ([point (in-vector endpoints)]) (if point 0 1))
           'on-termination on-termination
           ;; Independent computations have deterministic slots; field calls
           ;; remain serial in this pure layer until worker preparation lands.
           'parallel-mode (if parallel? 'independent 'serial))))

(define (flow-map3d-ref map index)
  (unless (prepared-flow-map3d? map) (raise-argument-error 'flow-map3d-ref "prepared-flow-map3d?" map))
  (unless (and (exact-nonnegative-integer? index) (< index (seed-set3d-count (prepared-flow-map3d-seeds map))))
    (raise-argument-error 'flow-map3d-ref "valid seed index" index))
  (vector-ref (prepared-flow-map3d-endpoints map) index))

(define (flow-map3d-pairs map)
  (unless (prepared-flow-map3d? map) (raise-argument-error 'flow-map3d-pairs "prepared-flow-map3d?" map))
  (vector->immutable-vector
   (list->vector
    (for/list ([seed (in-vector (seed-set3d-points (prepared-flow-map3d-seeds map)))]
               [endpoint (in-vector (prepared-flow-map3d-endpoints map))]
               #:when endpoint)
      (cons seed endpoint)))))

(define (flow-map3d-displacement map index)
  (define endpoint (flow-map3d-ref map index))
  (and endpoint (vec3- endpoint (vector-ref (seed-set3d-points (prepared-flow-map3d-seeds map)) index))))
