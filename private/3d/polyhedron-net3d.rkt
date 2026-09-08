#lang racket/base

;;;
;;; Polyhedral-net preparation
;;;

;; A prepared net is pure geometry: a face-adjacency spanning tree, a rigid
;; flattened frame per face, and a deterministic overlap report.  The later
;; animation layer can therefore rotate around these same hinges without ever
;; interpolating unrelated face vertices.

(require racket/list
         racket/set
         "mesh3d.rkt"
         "mesh-part-provenance3d.rkt"
         "mesh-topology3d.rkt"
         "net-overlap3d.rkt"
         "polyhedral-complex3d.rkt"
         "vec3.rkt")

(provide (struct-out net-overlap3d)
         (struct-out net-hinge3d)
         (struct-out net-face-transform3d)
         (struct-out polyhedron-net3d)
         polyhedron-net3d-face-child-ids
         prepare-polyhedron-net3d)

(struct net-hinge3d (parent child primal-edge) #:transparent)

;; A source point p maps to origin + dot(p-a,e)E + dot(p-a,f)F
;; + dot(p-a,n)N.  A face-plane point has zero final normal coordinate.
(struct net-face-transform3d
  (face source-origin source-e source-f source-n
        target-origin target-e target-f target-n)
  #:transparent)

(struct polyhedron-net3d
  (root-face hinge-tree cut-edges face-transforms flat-polygons overlaps diagnostics)
  #:transparent)

(struct face-adjacency-edge (index first second) #:transparent)
(struct net-layout (tree cuts transforms polygons overlaps score) #:transparent)


;;;
;;; Public preparation
;;;

; prepare-polyhedron-net3d
; : polyhedral-complex3d?
;   [#:root-face face-selector]
;   [#:hinges (or/c #f (listof topological-edge-index))]
;   [#:strategy (or/c 'breadth-first 'depth-first 'minimum-overlap)]
;   [#:search-limit exact-positive-integer?]
;   -> polyhedron-net3d?
;;
;; An explicit hinge set is a spanning tree of polygonal-face adjacency.  The
;; automatic minimum-overlap strategy enumerates tree candidates in edge-index
;; order, scores actual flattened overlap area before boundary crossings and
;; diameter, and honestly reports whether its search limit was reached.
(define (prepare-polyhedron-net3d complex
                                  #:root-face [root 0]
                                  #:hinges [hinges #f]
                                  #:strategy [strategy 'breadth-first]
                                  #:search-limit [limit 1000])
  (unless (polyhedral-complex3d? complex)
    (raise-argument-error 'prepare-polyhedron-net3d "polyhedral-complex3d?" complex))
  (unless (memq strategy '(breadth-first depth-first minimum-overlap))
    (raise-argument-error 'prepare-polyhedron-net3d
                          "'breadth-first, 'depth-first, or 'minimum-overlap"
                          strategy))
  (unless (exact-positive-integer? limit)
    (raise-argument-error 'prepare-polyhedron-net3d "exact-positive-integer?" limit))
  (define faces (polyhedral-complex3d-faces complex))
  (define face-count (vector-length faces))
  (unless (and (exact-nonnegative-integer? root) (< root face-count))
    (raise-argument-error 'prepare-polyhedron-net3d "an in-range face index" root))
  (for ([face (in-vector faces)])
    (unless (polyhedral-face3d-boundary-vertex-indices face)
      (raise-arguments-error
       'prepare-polyhedron-net3d "simple polygonal faces"
       "face" (polyhedral-face3d-id face))))
  (define face-edges (build-face-adjacency-edges complex))
  (define adjacency (build-face-adjacency face-count face-edges))
  (define-values (tree search-complete? candidate-count selected-score)
    (cond
      [hinges
       (define selected (checked-hinge-set hinges face-edges))
       (define tree (oriented-tree face-count adjacency root selected 'breadth-first))
       (unless (and (= (set-count selected) (sub1 face-count))
                    (= (length tree) (sub1 face-count))
                    (equal? selected
                            (list->set (map net-hinge3d-primal-edge tree))))
         (raise-arguments-error
          'prepare-polyhedron-net3d
          "a connected face-adjacency spanning tree"
          "hinges" hinges))
       (values tree #t 1 #f)]
      [(eq? strategy 'minimum-overlap)
       (choose-minimum-overlap-tree complex faces face-edges adjacency root limit)]
      [else
       (define tree (oriented-tree face-count adjacency root #f strategy))
       (unless (= (length tree) (sub1 face-count))
         (raise-arguments-error
          'prepare-polyhedron-net3d "a connected face-adjacency graph" "root" root))
       (values tree #t 1 #f)]))
  (define layout (build-net-layout complex faces face-edges root tree))
  (define score (or selected-score (net-layout-score layout)))
  (polyhedron-net3d
   root
   (vector->immutable-vector (list->vector tree))
   (net-layout-cuts layout)
   (net-layout-transforms layout)
   (net-layout-polygons layout)
   (net-layout-overlaps layout)
   (hasheq 'strategy strategy
           ;; A prepared net addresses its face children through stable symbols.
           ;; Explicit polygonal face identifiers are retained verbatim; generated
           ;; complex faces get deterministic `face-N` names instead.
           'face-child-ids (face-child-ids faces)
           'search-complete? search-complete?
           'search-limit limit
           'candidate-count candidate-count
           'selected-tree-edge-indices
           (vector->immutable-vector
            (list->vector (sort (map net-hinge3d-primal-edge tree) <)))
           'overlap-count (vector-length (net-layout-overlaps layout))
           'total-overlap-area (first score)
           'boundary-crossings (second score)
           'net-diameter (third score)
           'part-provenance
           (net-part-provenance complex faces tree (net-layout-cuts layout)))))

; polyhedron-net3d-face-child-ids : polyhedron-net3d? -> immutable-vectorof symbol?
;; Returns the stable direct-child IDs expected by polyhedron net fold/unfold
;; animations.  The vector index is the polygonal face index.
(define (polyhedron-net3d-face-child-ids net)
  (unless (polyhedron-net3d? net)
    (raise-argument-error 'polyhedron-net3d-face-child-ids "polyhedron-net3d?" net))
  (define ids (hash-ref (polyhedron-net3d-diagnostics net) 'face-child-ids #f))
  (unless (and (vector? ids) (andmap symbol? (vector->list ids)))
    (raise-arguments-error
     'polyhedron-net3d-face-child-ids
     "a prepared net with stable face child IDs"
     "net" net))
  ids)

(define (face-child-ids faces)
  (define ids
    (vector->immutable-vector
     (for/vector ([face (in-vector faces)] [index (in-naturals)])
       (define face-id (polyhedral-face3d-id face))
       (if (symbol? face-id)
           face-id
           (string->symbol (format "face-~a" index))))))
  (when (not (= (vector-length ids)
                (length (remove-duplicates (vector->list ids)))))
    (raise-arguments-error
     'prepare-polyhedron-net3d
     "unique symbolic polygonal face identities for a foldable net"
     "face-child-ids" ids))
  ids)

(define (net-part-provenance complex faces tree cuts)
  (define topology (polyhedral-complex3d-topology complex))
  ;; Flattening duplicates a shared source vertex once for each polygonal face
  ;; that owns it. The `(face-index local-boundary-index)` identity points into
  ;; `polyhedron-net3d-flat-polygons` without pretending the copies were still
  ;; one indexed mesh vertex.
  (define vertex-entries
    (vector->immutable-vector
     (for/vector ([source-index
                  (in-range (vector-length (mesh-topology3d-vertices topology)))])
       (define copies
         (apply append
                (for/list ([face (in-vector faces)] [face-index (in-naturals)])
                  (for/list ([vertex-index
                              (in-vector (polyhedral-face3d-boundary-vertex-indices face))]
                             [local-index (in-naturals)]
                             #:when (= vertex-index source-index))
                    (mesh-part-reference3d 'vertex (list face-index local-index))))))
       (mesh-part-provenance-entry3d
        (mesh-part-reference3d 'vertex source-index)
        (vector->immutable-vector (list->vector copies))
        (if (= (length copies) 1) 'preserved 'split)))))
  (define tree-edges (list->set (map net-hinge3d-primal-edge tree)))
  (define cut-edges (list->set (vector->list cuts)))
  (define edge-entries
    (vector->immutable-vector
     (for/vector ([source-index
                  (in-range (vector-length (mesh-topology3d-edges topology)))])
       (define result-parts
         (cond [(set-member? tree-edges source-index)
                (vector->immutable-vector
                 (vector (mesh-part-reference3d 'edge source-index)))]
               [(set-member? cut-edges source-index)
                (vector->immutable-vector
                 (vector (mesh-part-reference3d 'edge source-index)))]
               [else #()]))
       (mesh-part-provenance-entry3d
        (mesh-part-reference3d 'edge source-index)
        result-parts
        (cond [(set-member? tree-edges source-index) 'preserved]
              [(set-member? cut-edges source-index) 'split]
              [else 'discarded])))))
  (define face-entries
    (vector->immutable-vector
     (for/vector ([face-index (in-range (vector-length faces))])
       (mesh-part-provenance-entry3d
        (mesh-part-reference3d 'face face-index)
        (vector->immutable-vector
         (vector (mesh-part-reference3d 'face face-index)))
        'preserved))))
  (make-mesh-part-provenance3d
   #:vertices vertex-entries
   #:edges edge-entries
   #:faces face-entries
   #:warnings
   (vector-immutable 'net-vertex-copies-are-keyed-by-face-and-local-boundary-index)))


;;;
;;; Face-adjacency trees
;;;

(define (build-face-adjacency-edges complex)
  (define topology (polyhedral-complex3d-topology complex))
  (define edge-to-faces (polyhedral-complex3d-edge-to-faces complex))
  (for/list ([edge-index (in-range (vector-length (mesh-topology3d-edges topology)))]
             #:when (= (vector-length (vector-ref edge-to-faces edge-index)) 2))
    (define incident-faces (vector-ref edge-to-faces edge-index))
    (face-adjacency-edge edge-index
                         (min (vector-ref incident-faces 0) (vector-ref incident-faces 1))
                         (max (vector-ref incident-faces 0) (vector-ref incident-faces 1)))))

(define (build-face-adjacency face-count face-edges)
  (define adjacency (make-vector face-count '()))
  (for ([edge (in-list face-edges)])
    (vector-set! adjacency (face-adjacency-edge-first edge)
                 (cons (cons (face-adjacency-edge-second edge)
                             (face-adjacency-edge-index edge))
                       (vector-ref adjacency (face-adjacency-edge-first edge))))
    (vector-set! adjacency (face-adjacency-edge-second edge)
                 (cons (cons (face-adjacency-edge-first edge)
                             (face-adjacency-edge-index edge))
                       (vector-ref adjacency (face-adjacency-edge-second edge)))))
  (vector->immutable-vector
   (for/vector ([neighbours (in-vector adjacency)])
     (sort neighbours < #:key cdr))))

(define (checked-hinge-set hinges face-edges)
  (unless (list? hinges)
    (raise-argument-error 'prepare-polyhedron-net3d
                          "a list of topological edge indexes" hinges))
  (define available (list->set (map face-adjacency-edge-index face-edges)))
  (for ([edge-index (in-list hinges)])
    (unless (and (exact-nonnegative-integer? edge-index)
                 (set-member? available edge-index))
      (raise-arguments-error
       'prepare-polyhedron-net3d "a face-adjacency topological edge index"
       "hinge" edge-index)))
  (list->set hinges))

;; `allowed-edges` is #f for the full graph or a set of primal edge indexes.
(define (oriented-tree face-count adjacency root allowed-edges strategy)
  (define seen (make-hash))
  (hash-set! seen root #t)
  (let loop ([pending (list root)] [reversed-tree '()])
    (cond [(null? pending) (reverse reversed-tree)]
          [else
           (define parent (car pending))
           ;; A malformed complex can give the same two polygonal faces more
           ;; than one common topological edge.  The first source edge is the
           ;; only candidate allowed to discover that child; otherwise the
           ;; traversal would create two parent links and cease to be a tree.
           (define usable '())
           (define discovered-here (make-hash))
           (for ([entry (in-list (vector-ref adjacency parent))])
             (when (and (or (not allowed-edges)
                            (set-member? allowed-edges (cdr entry)))
                        (not (hash-has-key? seen (car entry)))
                        (not (hash-has-key? discovered-here (car entry))))
               (hash-set! discovered-here (car entry) #t)
               (set! usable (append usable (list entry)))))
           (for ([entry (in-list usable)])
             (hash-set! seen (car entry) #t))
           (define children (map car usable))
           (define next-pending
             (if (eq? strategy 'depth-first)
                 (append (reverse children) (cdr pending))
                 (append (cdr pending) children)))
           (loop next-pending
                 (append (reverse
                          (for/list ([entry (in-list usable)])
                            (net-hinge3d parent (car entry) (cdr entry))))
                         reversed-tree))])))


;;;
;;; Deterministic minimum-overlap search
;;;

(define (choose-minimum-overlap-tree complex faces face-edges adjacency root limit)
  (define face-count (vector-length faces))
  ;; One extra candidate tells us that the prescribed search limit was reached
  ;; without pretending that the first `limit` candidates were an exhaustive
  ;; search.  Candidate edge vectors are in increasing edge-index order.
  (define-values (candidate-edge-sets stopped?)
    (enumerate-spanning-edge-sets face-count face-edges (add1 limit)))
  (when (null? candidate-edge-sets)
    (raise-arguments-error
     'prepare-polyhedron-net3d "a connected face-adjacency spanning tree"
     "root" root))
  (define examined (take candidate-edge-sets (min limit (length candidate-edge-sets))))
  (define best
    (for/fold ([best #f]) ([edge-set (in-list examined)])
      (define tree (oriented-tree face-count adjacency root (list->set edge-set)
                                  'breadth-first))
      (define layout (build-net-layout complex faces face-edges root tree))
      (define candidate (cons tree (net-layout-score layout)))
      (if (or (not best) (net-score<? (cdr candidate) (cdr best)))
          candidate
          best)))
  (values (car best)
          (and (not stopped?) (<= (length candidate-edge-sets) limit))
          (length examined)
          (cdr best)))

(define (enumerate-spanning-edge-sets face-count face-edges cap)
  (define sorted-edges (sort face-edges < #:key face-adjacency-edge-index))
  (define collected '())
  (define stopped? #f)
  (define (visit start remaining chosen)
    (cond [(>= (length collected) cap) (set! stopped? #t)]
          [(zero? remaining)
           (when (edge-set-spans? face-count chosen)
             (set! collected
                   (append collected
                           (list (sort (map face-adjacency-edge-index chosen) <)))))]
          [else
           (define last-start (- (length sorted-edges) remaining))
           (for ([index (in-range start (add1 last-start))])
             (unless stopped?
               (visit (add1 index) (sub1 remaining)
                      (append chosen (list (list-ref sorted-edges index))))))]))
  (visit 0 (sub1 face-count) '())
  (values collected stopped?))

(define (edge-set-spans? face-count edges)
  (and (= (length edges) (sub1 face-count))
       (let ([adjacency (make-vector face-count '())])
         (for ([edge (in-list edges)])
           (vector-set! adjacency (face-adjacency-edge-first edge)
                        (cons (face-adjacency-edge-second edge)
                              (vector-ref adjacency (face-adjacency-edge-first edge))))
           (vector-set! adjacency (face-adjacency-edge-second edge)
                        (cons (face-adjacency-edge-first edge)
                              (vector-ref adjacency (face-adjacency-edge-second edge)))))
         (define seen (make-hash))
         (let visit ([pending '(0)])
           (cond [(null? pending) (= (hash-count seen) face-count)]
                 [else
                  (define current (car pending))
                  (if (hash-has-key? seen current)
                      (visit (cdr pending))
                      (begin
                        (hash-set! seen current #t)
                        (visit (append (cdr pending)
                                       (vector-ref adjacency current)))))])))))


;;;
;;; Rigid flattening and overlap score
;;;

(define (build-net-layout complex faces face-edges root tree)
  (define topology (polyhedral-complex3d-topology complex))
  ;; Nets are constructed from the canonical, world-space analysis mesh.
  (define vertices (mesh3d-vertices (polyhedral-complex3d-analysis-mesh complex)))
  (define root-face (vector-ref faces root))
  (define root-normal (polyhedral-face3d-normal root-face))
  (define maps (make-vector (vector-length faces) #f))
  (define root-boundary (polyhedral-face3d-boundary-vertex-indices root-face))
  (define root-a (vector-ref root-boundary 0))
  (define root-b (vector-ref root-boundary 1))
  (vector-set! maps root
               (make-net-map root-face vertices root-normal root-a root-b
                             (vector-ref vertices root-a)
                             (vector-ref vertices root-b)))
  ;; `tree` is parent-before-child by construction, so each child uses a final
  ;; parent frame.  The shared topological edge, not a face's first boundary
  ;; edge, is the source axis; this matters for general polygonal faces.
  (for ([hinge (in-list tree)])
    (define edge
      (mesh-edge-topology3d-vertices
       (vector-ref (mesh-topology3d-edges topology)
                   (net-hinge3d-primal-edge hinge))))
    (define source-a (vector-ref edge 0))
    (define source-b (vector-ref edge 1))
    (define parent-map (vector-ref maps (net-hinge3d-parent hinge)))
    (define child-face (vector-ref faces (net-hinge3d-child hinge)))
    (define child-map
      (make-net-map child-face vertices root-normal source-a source-b
                    (net-map-apply parent-map (vector-ref vertices source-a))
                    (net-map-apply parent-map (vector-ref vertices source-b))))
    ;; A rigid face has two coplanar choices about a hinge.  Select the one
    ;; opposite the parent interior; choosing the same side collapses ordinary
    ;; cube faces directly on top of their parent.
    (define parent-centroid
      (net-map-apply parent-map
                     (polyhedral-face3d-centroid
                      (vector-ref faces (net-hinge3d-parent hinge)))))
    (define parent-side
      (vec3-dot
       (vec3- parent-centroid (net-face-transform3d-target-origin child-map))
       (net-face-transform3d-target-f child-map)))
    (define child-side
      (vec3-dot
       (vec3- (polyhedral-face3d-centroid child-face)
              (net-face-transform3d-source-origin child-map))
       (net-face-transform3d-source-f child-map)))
    (define unfolded-child-map
      (if (positive? (* parent-side child-side))
          ;; Flip both perpendicular axes to retain an orientation-preserving
          ;; frame.  `target-n` is not a cosmetic field: it is the normal axis
          ;; used later by fold/unfold rotations.
          (struct-copy net-face-transform3d child-map
                       [target-f
                        (vec3-scale -1 (net-face-transform3d-target-f child-map))]
                       [target-n
                        (vec3-scale -1 (net-face-transform3d-target-n child-map))])
          child-map))
    (vector-set! maps (net-hinge3d-child hinge) unfolded-child-map))
  (define transforms
    (vector->immutable-vector
     (for/vector ([transform (in-vector maps)] [face-index (in-naturals)])
       (unless transform
         (raise-arguments-error
          'prepare-polyhedron-net3d "a parent-before-child spanning tree"
          "unmapped-face" face-index))
       (struct-copy net-face-transform3d transform [face face-index]))))
  (define polygons
    (vector->immutable-vector
     (for/vector ([face (in-vector faces)] [transform (in-vector transforms)])
       (vector->immutable-vector
        (for/vector ([vertex-index
                      (in-vector (polyhedral-face3d-boundary-vertex-indices face))])
          (net-map-apply transform (vector-ref vertices vertex-index)))))))
  (define root-map (vector-ref transforms root))
  (define overlaps
    (net-polygons-overlaps3d polygons
                             (net-face-transform3d-target-origin root-map)
                             (net-face-transform3d-target-e root-map)
                             (net-face-transform3d-target-f root-map)))
  (define tree-edge-set (list->set (map net-hinge3d-primal-edge tree)))
  (define cuts
    (vector->immutable-vector
     (for/vector ([edge (in-list face-edges)]
                  #:unless (set-member? tree-edge-set
                                        (face-adjacency-edge-index edge)))
       (face-adjacency-edge-index edge))))
  (net-layout tree cuts transforms polygons overlaps
              (list (for/sum ([overlap (in-vector overlaps)])
                      (net-overlap3d-area overlap))
                    (for/sum ([overlap (in-vector overlaps)])
                      (net-overlap3d-boundary-crossings overlap))
                    (net-diameter polygons root-map))))

(define (make-net-map face vertices root-normal source-a-index source-b-index
                      target-a target-b)
  (define source-e
    (vec3-normalize
     (vec3- (vector-ref vertices source-b-index)
            (vector-ref vertices source-a-index))))
  (define source-n (polyhedral-face3d-normal face))
  (define source-f (vec3-cross source-n source-e))
  (define target-e (vec3-normalize (vec3- target-b target-a)))
  (define target-f (vec3-cross root-normal target-e))
  (net-face-transform3d #f (vector-ref vertices source-a-index)
                        source-e source-f source-n
                        target-a target-e target-f root-normal))

(define (net-map-apply transform point)
  (define offset (vec3- point (net-face-transform3d-source-origin transform)))
  (vec3+
   (net-face-transform3d-target-origin transform)
   (vec3+
    (vec3-scale (vec3-dot offset (net-face-transform3d-source-e transform))
                (net-face-transform3d-target-e transform))
    (vec3+
     (vec3-scale (vec3-dot offset (net-face-transform3d-source-f transform))
                 (net-face-transform3d-target-f transform))
     (vec3-scale (vec3-dot offset (net-face-transform3d-source-n transform))
                 (net-face-transform3d-target-n transform))))))

(define (net-score<? left right)
  (cond [(< (first left) (first right)) #t]
        [(> (first left) (first right)) #f]
        [(< (second left) (second right)) #t]
        [(> (second left) (second right)) #f]
        [else (< (third left) (third right))]))

(define (net-diameter polygons root-map)
  (define origin (net-face-transform3d-target-origin root-map))
  (define basis-e (net-face-transform3d-target-e root-map))
  (define basis-f (net-face-transform3d-target-f root-map))
  (define coordinates
    (append*
     (for/list ([polygon (in-vector polygons)])
       (for/list ([point (in-vector polygon)])
         (define offset (vec3- point origin))
         (cons (vec3-dot offset basis-e) (vec3-dot offset basis-f))))))
  (define xs (map car coordinates))
  (define ys (map cdr coordinates))
  (define width (- (apply max xs) (apply min xs)))
  (define height (- (apply max ys) (apply min ys)))
  (sqrt (+ (* width width) (* height height))))
