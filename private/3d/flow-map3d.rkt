#lang racket/base

(require racket/list
         "../geometry.rkt" "ode-flow3d.rkt" "point-line-arrow3d.rkt"
         "linear3.rkt" "material3d.rkt" "mesh3d.rkt" "seed-set3d.rkt"
         "spatial-group.rkt" "vec3.rkt")

(provide (struct-out prepared-flow-map3d)
         prepare-flow-map3d flow-map3d-ref flow-map3d-pairs flow-map3d-displacement
         flow-map-grid3d flow-volume-cell3d
         flow-map3d-local-jacobian flow-map3d-volume-factor)

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

;; A grid cell has a concrete source neighbourhood, unlike a loose collection
;; of seeds.  Cell indices enumerate lower grid corners in retained seed order;
;; the eight vertices themselves retain the source's x/y/z orientation rather
;; than assuming that a particular seed-order spelling is in use.
(define (flow-volume-cell3d map cell-index
                            #:id [id #f]
                            #:material [material default-material3d])
  (unless (prepared-flow-map3d? map)
    (raise-argument-error 'flow-volume-cell3d "prepared-flow-map3d?" map))
  (unless (exact-nonnegative-integer? cell-index)
    (raise-argument-error 'flow-volume-cell3d "exact-nonnegative-integer? as cell-index" cell-index))
  (when (and id (not (symbol? id)))
    (raise-argument-error 'flow-volume-cell3d "(or/c #f symbol?) as #:id" id))
  (unless (material3d? material)
    (raise-argument-error 'flow-volume-cell3d "material3d? as #:material" material))
  (define seeds (prepared-flow-map3d-seeds map))
  (unless (eq? (seed-set3d-kind seeds) 'grid)
    (raise-arguments-error 'flow-volume-cell3d "an explicitly structured grid seed set"
                           "seed-kind" (seed-set3d-kind seeds)))
  (define cells (grid-cell-indices (seed-set3d-points seeds)))
  (unless (< cell-index (vector-length cells))
    (raise-arguments-error 'flow-volume-cell3d "a valid retained grid cell index"
                           "cell-index" cell-index
                           "cell-count" (vector-length cells)))
  (define source-indices (vector-ref cells cell-index))
  (define endpoints (prepared-flow-map3d-endpoints map))
  (define vertices
    (for/vector ([source-index (in-vector source-indices)])
      (define endpoint (vector-ref endpoints source-index))
      (unless endpoint
        (raise-arguments-error 'flow-volume-cell3d
                               "endpoints for all eight requested grid-cell vertices"
                               "cell-index" cell-index
                               "seed-index" source-index))
      endpoint))
  (mesh3d #:id (or id (string->symbol (format "flow-volume-cell-~a" cell-index)))
          #:vertices vertices
          #:material material
          ;; The indices are x/y/z corners 000,100,010,110,001,101,011,111.
          ;; Every face has a stable outward winding for an orientation-
          ;; preserving map. A negative volume factor naturally reverses its
          ;; physical orientation; the geometry does not conceal that fact.
          #:triangles
          (vector (vector 0 2 1) (vector 1 2 3) ; z-
                  (vector 4 5 6) (vector 5 7 6) ; z+
                  (vector 0 1 4) (vector 1 5 4) ; y-
                  (vector 2 6 3) (vector 3 6 7) ; y+
                  (vector 0 4 2) (vector 2 4 6) ; x-
                  (vector 1 3 5) (vector 3 7 5)))) ; x+

;; -> immutable-vectorof eight-index vectors. The semantic cell order is
;; determined by source coordinates, not by the optional `grid-seeds3d`
;; declaration order. This makes the API stable for all supported grid orders.
(define (grid-cell-indices points)
  (vector->immutable-vector
   (list->vector
    (for/list ([origin (in-range (vector-length points))]
               #:do [(define x (grid-axis-successor points origin 0))
                     (define y (grid-axis-successor points origin 1))
                     (define z (grid-axis-successor points origin 2))]
               #:when (and x y z))
      (define xy (and x (grid-axis-successor points x 1)))
      (define xz (and x (grid-axis-successor points x 2)))
      (define yz (and y (grid-axis-successor points y 2)))
      (define xyz (and xy (grid-axis-successor points xy 2)))
      ;; A regular grid supplies all of these. Keeping the check makes this
      ;; helper truthful if a future grid provenance admits holes.
      (unless (and xy xz yz xyz)
        (raise-arguments-error 'flow-volume-cell3d
                               "complete explicit grid cells"
                               "origin-index" origin))
      (vector-immutable origin x y xy z xz yz xyz)))))

(define (grid-axis-successor points index axis)
  (define source (vector-ref points index))
  (for/fold ([best #f]) ([candidate-index (in-range (vector-length points))]
                         #:unless (= candidate-index index))
    (define candidate (vector-ref points candidate-index))
    (if (and (for/and ([other-axis '(0 1 2)] #:unless (= other-axis axis))
              (= (coordinate candidate other-axis) (coordinate source other-axis)))
             (> (coordinate candidate axis) (coordinate source axis))
             (or (not best)
                 (< (coordinate candidate axis)
                    (coordinate (vector-ref points best) axis))))
        candidate-index
        best)))

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
