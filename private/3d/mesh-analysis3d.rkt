#lang racket/base

;;;
;;; Immutable Indexed-Mesh Diagnostics
;;;

;; Analyses a mesh without changing it.  Reports preserve source index order so
;; a diagnostic can be mapped back to an authored face, edge, or vertex without
;; relying on an implementation hash-table traversal.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "bounds3.rkt"
         "edge-adjacency3d.rkt"
         "mesh3d.rkt"
         "vec3.rkt")

(provide (struct-out mesh3d-duplicate-triangle)
         (struct-out mesh3d-analysis)
         analyze-mesh3d
         mesh3d-validate
         mesh3d-orientation-parities)


;;;
;;; Immutable Reports
;;;

(struct mesh3d-duplicate-triangle
  (first-triangle-index duplicate-triangle-index winding)
  #:transparent)

;; mesh3d-duplicate-triangle identifies a later face with the same three
;; indexed vertices. `winding` is 'same or 'reversed relative to the first.

(struct mesh3d-analysis
  (vertex-count
   triangle-count
   edge-count
   degenerate-triangles
   duplicate-triangles
   boundary-edges
   boundary-loops
   nonmanifold-edges
   inconsistent-winding-edges
   connected-components
   isolated-vertices
   signed-component-volumes
   watertight?
   orientable?
   consistently-wound?)
  #:transparent)

;; mesh3d-analysis is a pure topology/geometry report.
;;  - edge collections contain edge-adjacency3d values in encounter order.
;;  - loops/components are immutable vectors ordered by their smallest source
;;    index; signed volumes align with connected-components.


;;;
;;; Public Analysis
;;;

; analyze-mesh3d : mesh3d? -> mesh3d-analysis?
;;   Computes deterministic geometric and combinatorial diagnostics for mesh.
(define (analyze-mesh3d mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'analyze-mesh3d "mesh3d?" mesh))
  (define vertices (mesh3d-vertices mesh))
  (define triangles (mesh3d-triangles mesh))
  (define adjacency (mesh3d-edge-adjacency mesh))
  (define degenerates (degenerate-triangle-indices mesh))
  (define duplicates (duplicate-triangles triangles))
  (define boundaries
    (filter-adjacency adjacency (lambda (entry) (= (vector-length (edge-adjacency3d-incidences entry)) 1))))
  (define nonmanifolds
    (filter-adjacency adjacency (lambda (entry) (> (vector-length (edge-adjacency3d-incidences entry)) 2))))
  (define inconsistent
    (filter-adjacency adjacency inconsistent-winding-edge?))
  (define components (triangle-components (vector-length triangles) adjacency))
  (define isolated (isolated-vertex-indices mesh))
  (define-values (_parities orientation-conflict?)
    (mesh3d-orientation-parities mesh adjacency))
  (define volumes
    (vector->immutable-vector
     (for/vector ([component (in-vector components)])
       (component-signed-volume mesh component))))
  (define watertight?
    (and (positive? (vector-length triangles))
         (zero? (vector-length boundaries))
         (zero? (vector-length nonmanifolds))
         (zero? (vector-length degenerates))))
  (define orientable? (not orientation-conflict?))
  (define consistently-wound?
    (and orientable?
         (zero? (vector-length nonmanifolds))
         (zero? (vector-length inconsistent))))
  (mesh3d-analysis
   (vector-length vertices)
   (vector-length triangles)
   (vector-length adjacency)
   degenerates
   duplicates
   boundaries
   (boundary-loops boundaries (vector-length vertices))
   nonmanifolds
   inconsistent
   components
   isolated
   volumes
   watertight?
   orientable?
   consistently-wound?))

; mesh3d-validate : mesh3d? -> mesh3d-analysis?
;;   Returns the explicit diagnostic report for a structurally valid mesh.
;;
;; `mesh3d` already rejects malformed container values.  This separate query
;; keeps potentially costly topology checks and all diagnostic policy out of
;; ordinary mesh construction.
(define (mesh3d-validate mesh)
  (analyze-mesh3d mesh))


;;;
;;; Geometric Diagnostics
;;;

; degenerate-triangle-indices : mesh3d? -> immutable-vectorof exact-nonnegative-integer?
;;   Finds faces whose doubled area is tiny relative to the mesh extent.
(define (degenerate-triangle-indices mesh)
  (define tolerance (mesh-area-tolerance mesh))
  (vector->immutable-vector
   (for/vector ([triangle (in-vector (mesh3d-triangles mesh))]
                [index (in-naturals)]
                #:when (<= (triangle-double-area mesh triangle) tolerance))
     index)))

; mesh-area-tolerance : mesh3d? -> nonnegative-real?
;;   Gives a scale-aware tolerance in squared world-coordinate units.
(define (mesh-area-tolerance mesh)
  (define bounds (mesh3d-local-bounds mesh))
  (cond [(aabb3-empty? bounds) 0]
        [else
         (define extent (vec3-length (aabb3-size bounds)))
         ;; The floor only covers a mesh collapsed to a single floating-point
         ;; coordinate.  For nontrivial geometry the tolerance scales with
         ;; squared extent, rather than applying one absolute world threshold.
         (max 1e-30 (* 1e-10 extent extent))]))

(define (triangle-double-area mesh triangle)
  (define points
    (for/list ([index (in-vector triangle)])
      (vector-ref (mesh3d-vertices mesh) index)))
  (vec3-length
   (vec3-cross (vec3- (second points) (first points))
               (vec3- (third points) (first points)))))

(define (duplicate-triangles triangles)
  (define first-by-signature (make-hash))
  (define reversed '())
  (for ([triangle (in-vector triangles)] [triangle-index (in-naturals)])
    (define signature (sort (vector->list triangle) <))
    (define first-index (hash-ref first-by-signature signature #f))
    (cond [first-index
           (define first-triangle (vector-ref triangles first-index))
           (set! reversed
                 (cons (mesh3d-duplicate-triangle
                        first-index triangle-index
                        (if (same-cyclic-winding? first-triangle triangle)
                            'same
                            'reversed))
                       reversed))]
          [else (hash-set! first-by-signature signature triangle-index)]))
  (vector->immutable-vector (list->vector (reverse reversed))))

(define (same-cyclic-winding? first second)
  (for/or ([shift (in-range 3)])
    (and (= (vector-ref first 0) (vector-ref second shift))
         (= (vector-ref first 1) (vector-ref second (modulo (add1 shift) 3)))
         (= (vector-ref first 2) (vector-ref second (modulo (+ shift 2) 3))))))


;;;
;;; Combinatorial Diagnostics
;;;

(define (filter-adjacency adjacency predicate)
  (vector->immutable-vector
   (for/vector ([entry (in-vector adjacency)] #:when (predicate entry)) entry)))

(define (inconsistent-winding-edge? entry)
  (and (= (vector-length (edge-adjacency3d-incidences entry)) 2)
       (let ([first (vector-ref (edge-adjacency3d-incidences entry) 0)]
             [second (vector-ref (edge-adjacency3d-incidences entry) 1)])
         (and (= (edge-incidence3d-from-index first)
                 (edge-incidence3d-from-index second))
              (= (edge-incidence3d-to-index first)
                 (edge-incidence3d-to-index second))))))

; mesh3d-orientation-parities : mesh3d? [immutable-vectorof edge-adjacency3d?]
;                              -> (values immutable-vector? boolean?)
;;   Assigns every face a required winding-flip parity; #t reports a conflict.
(define (mesh3d-orientation-parities mesh [adjacency (mesh3d-edge-adjacency mesh)])
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-orientation-parities "mesh3d?" mesh))
  (define count (vector-length (mesh3d-triangles mesh)))
  (define neighbours (make-vector count '()))
  (for ([entry (in-vector adjacency)]
        #:when (= (vector-length (edge-adjacency3d-incidences entry)) 2))
    (define first (vector-ref (edge-adjacency3d-incidences entry) 0))
    (define second (vector-ref (edge-adjacency3d-incidences entry) 1))
    ;; Equal directed traversals need one triangle flipped; opposed traversals
    ;; need equal flip parity.  Append preserves edge-incidence encounter order.
    (define required-xor
      (if (and (= (edge-incidence3d-from-index first) (edge-incidence3d-from-index second))
               (= (edge-incidence3d-to-index first) (edge-incidence3d-to-index second)))
          1
          0))
    (define first-index (edge-incidence3d-triangle-index first))
    (define second-index (edge-incidence3d-triangle-index second))
    (vector-set! neighbours first-index
                 (append (vector-ref neighbours first-index)
                         (list (cons second-index required-xor))))
    (vector-set! neighbours second-index
                 (append (vector-ref neighbours second-index)
                         (list (cons first-index required-xor)))))
  (define parities (make-vector count #f))
  (define conflict? #f)
  (for ([root (in-range count)])
    (when (not (vector-ref parities root))
      (vector-set! parities root 0)
      (let visit ([pending (list root)])
        (unless (null? pending)
          (define current (car pending))
          (define remaining (cdr pending))
          (define current-parity (vector-ref parities current))
          (define extended
            (for/fold ([queue remaining]) ([relation (in-list (vector-ref neighbours current))])
              (define other (car relation))
              (define expected (modulo (+ current-parity (cdr relation)) 2))
              (define observed (vector-ref parities other))
              (cond [(not observed)
                     (vector-set! parities other expected)
                     (append queue (list other))]
                    [(not (= observed expected))
                     (set! conflict? #t)
                     queue]
                    [else queue])))
          (visit extended)))))
  (values (vector->immutable-vector parities) conflict?))

(define (triangle-components triangle-count adjacency)
  (define neighbours (make-vector triangle-count '()))
  (for ([entry (in-vector adjacency)]
        #:when (>= (vector-length (edge-adjacency3d-incidences entry)) 2))
    (define indices
      (for/list ([incidence (in-vector (edge-adjacency3d-incidences entry))])
        (edge-incidence3d-triangle-index incidence)))
    (for ([first (in-list indices)])
      (for ([second (in-list indices)] #:unless (= first second))
        (vector-set! neighbours first
                     (append (vector-ref neighbours first) (list second))))))
  (define seen (make-vector triangle-count #f))
  (define components '())
  (for ([root (in-range triangle-count)])
    (unless (vector-ref seen root)
      (vector-set! seen root #t)
      (define component
        (let visit ([pending (list root)] [reversed '()])
          (cond [(null? pending) (sort reversed <)]
                [else
                 (define current (car pending))
                 (define next-pending
                   (for/fold ([queue (cdr pending)]) ([other (in-list (vector-ref neighbours current))])
                     (if (vector-ref seen other)
                         queue
                         (begin (vector-set! seen other #t)
                                (append queue (list other))))))
                 (visit next-pending (cons current reversed))])))
      (set! components (append components (list component)))))
  (vector->immutable-vector
   (list->vector
    (for/list ([component (in-list components)])
      (vector->immutable-vector (list->vector component))))))

(define (isolated-vertex-indices mesh)
  (define used (make-vector (vector-length (mesh3d-vertices mesh)) #f))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (for ([index (in-vector triangle)]) (vector-set! used index #t)))
  (for ([edge (in-vector (mesh3d-edges mesh))])
    (for ([index (in-vector edge)]) (vector-set! used index #t)))
  (vector->immutable-vector
   (for/vector ([present? (in-vector used)] [index (in-naturals)] #:unless present?) index)))

(define (component-signed-volume mesh component)
  (/ (for/sum ([triangle-index (in-vector component)])
       (define triangle (vector-ref (mesh3d-triangles mesh) triangle-index))
       (define first (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 0)))
       (define second (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 1)))
       (define third (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 2)))
       (vec3-dot first (vec3-cross second third)))
     6))


;;;
;;; Boundary Loops
;;;

;; Boundary input remains in edge-incidence order.  This walker intentionally
;; makes an explicit deterministic choice at a malformed boundary branch;
;; simple manifold loops are therefore reported as the familiar closed vertex
;; sequence while malformed chains remain inspectable rather than failing.
(define (boundary-loops boundary-edges vertex-count)
  (define count (vector-length boundary-edges))
  (define incident-edges (make-vector vertex-count '()))
  (for ([entry (in-vector boundary-edges)] [edge-index (in-naturals)])
    (define edge (edge-adjacency3d-edge entry))
    (for ([vertex (in-list (list (vector-ref edge 0) (vector-ref edge 1)))])
      (vector-set! incident-edges vertex
                   (append (vector-ref incident-edges vertex) (list edge-index)))))
  (define used (make-vector count #f))
  (define loops '())
  (for ([seed (in-range count)] #:unless (vector-ref used seed))
    (define component-edges (boundary-component seed boundary-edges incident-edges))
    (define degrees (make-hash))
    (for ([edge-index (in-list component-edges)])
      (define edge (edge-adjacency3d-edge (vector-ref boundary-edges edge-index)))
      (for ([vertex (in-vector edge)])
        (hash-set! degrees vertex (add1 (hash-ref degrees vertex 0)))))
    (define vertices (sort (hash-keys degrees) <))
    (define starts (filter (lambda (vertex) (not (= (hash-ref degrees vertex) 2))) vertices))
    (define start (if (null? starts) (car vertices) (car starts)))
    (define path
      (let walk ([current start] [reversed (list start)] [steps 0])
        (define candidates
          (filter (lambda (edge-index) (not (vector-ref used edge-index)))
                  (vector-ref incident-edges current)))
        (cond [(or (null? candidates) (>= steps (length component-edges)))
               (reverse reversed)]
              [else
               (define edge-index (car (sort candidates <)))
               (vector-set! used edge-index #t)
               (define edge (edge-adjacency3d-edge (vector-ref boundary-edges edge-index)))
               (define next
                 (if (= current (vector-ref edge 0))
                     (vector-ref edge 1)
                     (vector-ref edge 0)))
               (walk next (cons next reversed) (add1 steps))])))
    ;; A branch can leave an unused side edge. The outer seed traversal reports
    ;; it as another deterministic chain rather than silently dropping it.
    (set! loops
          (append loops
                  (list (vector->immutable-vector (list->vector path))))))
  (vector->immutable-vector (list->vector loops)))

(define (boundary-component seed boundary-edges incident-edges)
  (let visit ([pending (list seed)] [seen '()])
    (cond [(null? pending) (sort seen <)]
          [else
           (define edge-index (car pending))
           (cond [(member edge-index seen)
                  (visit (cdr pending) seen)]
                 [else
                  (define edge (edge-adjacency3d-edge (vector-ref boundary-edges edge-index)))
                  (define neighbours
                    (append (vector-ref incident-edges (vector-ref edge 0))
                            (vector-ref incident-edges (vector-ref edge 1))))
                  (visit (append (cdr pending) neighbours)
                         (cons edge-index seen))])])))
