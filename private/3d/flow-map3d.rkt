#lang racket/base

(require racket/list
         "../geometry.rkt" "ode-flow3d.rkt" "point-line-arrow3d.rkt"
         "linear3.rkt" "seed-set3d.rkt" "spatial-group.rkt" "vec3.rkt")

(provide (struct-out prepared-flow-map3d)
         prepare-flow-map3d flow-map3d-ref flow-map3d-pairs flow-map3d-displacement
         flow-map-grid3d flow-map3d-local-jacobian flow-map3d-volume-factor)

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
  (define field-key (and (ode-field3d? field) (ode-field3d-cache-key field)))
  (define cacheability (if field-key 'persistent-candidate 'memory-only))
  (define preparation-key
    (and field-key
         (list 'prepared-flow-map3d 'schema-1 field-key solver
               (seed-set3d-cache-key seeds) termination start-time end-time on-termination)))
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
           'cacheability cacheability
           'preparation-key preparation-key
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

;; Connect neighbouring cells in retained grid declaration order.  Missing
;; endpoints break an edge rather than drawing a fictional continuation.
(define (flow-map-grid3d map #:id [id 'flow-map-grid] #:connectivity [connectivity 'axis-neighbours])
  (unless (prepared-flow-map3d? map) (raise-argument-error 'flow-map-grid3d "prepared-flow-map3d?" map))
  (unless (symbol? id) (raise-argument-error 'flow-map-grid3d "symbol? as #:id" id))
  (unless (eq? connectivity 'axis-neighbours)
    (raise-argument-error 'flow-map-grid3d "'axis-neighbours as #:connectivity" connectivity))
  (define seeds (prepared-flow-map3d-seeds map))
  (unless (eq? (seed-set3d-kind seeds) 'grid)
    (raise-arguments-error 'flow-map-grid3d "an explicitly structured grid seed set"
                           "seed-kind" (seed-set3d-kind seeds)))
  (define points (seed-set3d-points seeds))
  (define endpoints (prepared-flow-map3d-endpoints map))
  (define pairs
    (for*/list ([i (in-range (vector-length points))]
                [j (in-range (add1 i) (vector-length points))]
                #:when (grid-neighbours? points i j))
      (cons i j)))
  (group3d
   (for/list ([pair (in-list pairs)] [edge-index (in-naturals)]
              #:when (and (vector-ref endpoints (car pair)) (vector-ref endpoints (cdr pair))))
     (line3d (vector-ref endpoints (car pair)) (vector-ref endpoints (cdr pair))
             #:id (string->symbol (format "edge-~a" edge-index))))
   #:id id))

(define (grid-neighbours? points i j)
  (define a (vector-ref points i)) (define b (vector-ref points j))
  (define differing
    (for/list ([axis '(0 1 2)] #:when (not (= (coordinate a axis) (coordinate b axis)))) axis))
  (and (= (length differing) 1)
       (let ([axis (car differing)] [low (min (coordinate a (car differing)) (coordinate b (car differing)))]
             [high (max (coordinate a (car differing)) (coordinate b (car differing)))])
         (not (for/or ([middle (in-vector points)])
                (and (= (coordinate middle (modulo (+ axis 1) 3))
                        (coordinate a (modulo (+ axis 1) 3)))
                     (= (coordinate middle (modulo (+ axis 2) 3))
                        (coordinate a (modulo (+ axis 2) 3)))
                     (< low (coordinate middle axis) high)))))))
(define (coordinate point axis)
  (case axis [(0) (vec3-x point)] [(1) (vec3-y point)] [else (vec3-z point)]))

;; A local derivative is meaningful here only because grid provenance supplies
;; a physical neighbourhood.  Central differences are preferred; a boundary
;; uses its one retained adjacent cell deterministically.
(define (flow-map3d-local-jacobian map index)
  (unless (prepared-flow-map3d? map) (raise-argument-error 'flow-map3d-local-jacobian "prepared-flow-map3d?" map))
  (define seeds (prepared-flow-map3d-seeds map))
  (unless (eq? (seed-set3d-kind seeds) 'grid)
    (raise-arguments-error 'flow-map3d-local-jacobian "an explicit grid seed set" "seed-kind" (seed-set3d-kind seeds)))
  (define points (seed-set3d-points seeds))
  (define endpoints (prepared-flow-map3d-endpoints map))
  (define source (vector-ref points index))
  (define endpoint (vector-ref endpoints index))
  (unless endpoint (raise-arguments-error 'flow-map3d-local-jacobian "an endpoint at the requested seed" "index" index))
  (define columns
    (for/list ([axis '(0 1 2)])
      (define candidates
        (for/list ([j (in-range (vector-length points))]
                   #:when (and (not (= j index))
                               (vector-ref endpoints j)
                               (for/and ([other '(0 1 2)] #:unless (= other axis))
                                 (= (coordinate (vector-ref points j) other) (coordinate source other))))) j))
      (define minus (for/first ([j (in-list candidates)] #:when (< (coordinate (vector-ref points j) axis) (coordinate source axis))) j))
      (define plus (for/first ([j (in-list candidates)] #:when (> (coordinate (vector-ref points j) axis) (coordinate source axis))) j))
      (cond [(and minus plus)
             (vec3-scale (/ 1 (- (coordinate (vector-ref points plus) axis) (coordinate (vector-ref points minus) axis)))
                         (vec3- (vector-ref endpoints plus) (vector-ref endpoints minus)))]
            [plus (vec3-scale (/ 1 (- (coordinate (vector-ref points plus) axis) (coordinate source axis)))
                              (vec3- (vector-ref endpoints plus) endpoint))]
            [minus (vec3-scale (/ 1 (- (coordinate source axis) (coordinate (vector-ref points minus) axis)))
                               (vec3- endpoint (vector-ref endpoints minus)))]
            [else (raise-arguments-error 'flow-map3d-local-jacobian "a retained adjacent endpoint on every grid axis" "axis" axis "index" index)])))
  (define dx (first columns)) (define dy (second columns)) (define dz (third columns))
  (linear3 (vec3-x dx) (vec3-x dy) (vec3-x dz)
           (vec3-y dx) (vec3-y dy) (vec3-y dz)
           (vec3-z dx) (vec3-z dy) (vec3-z dz)))

(define (flow-map3d-volume-factor map index)
  (linear3-determinant (flow-map3d-local-jacobian map index)))
