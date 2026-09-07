#lang racket/base

;;;
;;; Conservative Mesh Correspondence Planning
;;;

;; A correspondence is a source-index -> destination-index plan, not an
;; animation.  The plan must explain a match before any geometry moves.  In
;; particular, a symmetric local signature is never promoted to an arbitrary
;; graph-isomorphism claim.

(require racket/list
         racket/vector
         "../geometry.rkt"
         "mesh3d.rkt"
         "mesh-topology3d.rkt"
         "vec3.rkt")

(provide (struct-out spatial-correspondence3d)
         (struct-out mesh-correspondence3d)
         prepare-mesh-correspondence3d)

(struct spatial-correspondence3d (source destination reason mode route diagnostics)
  #:transparent)

;; Maps are immutable source-index -> destination-index vectors.  The two
;; unmatched fields are hashes keyed by 'vertex, 'edge, and 'face, preserving
;; the part kind instead of conflating vertices with render triangles.
(struct mesh-correspondence3d
  (vertex-map edge-map face-map unmatched-source unmatched-destination diagnostics)
  #:transparent)

(struct part-map-result (map reason ambiguities unmatched-signatures geometric-diagnostics)
  #:transparent)


;;;
;;; Public planner
;;;

; prepare-mesh-correspondence3d
; : mesh3d? mesh3d?
;   [#:vertex-map (or/c #f vector?)]
;   [#:edge-map (or/c #f vector?)]
;   [#:face-map (or/c #f vector?)]
;   [#:geometric-fallback? boolean?]
;   [#:geometric-frame 'local-normalized]
;   [#:geometric-limit exact-positive-integer?]
;   [#:maximum-geometric-cost (or/c #f nonnegative-finite-real?)]
;   -> mesh-correspondence3d?
;;
;; Priority is explicit author map, shared semantic IDs, identical indexed
;; topology, then a unique local topological signature.  Geometric matching is
;; intentionally an opt-in final layer: proximity must never be the default
;; for a symmetric mesh with several plausible correspondences.  Its declared
;; comparison frame is a centered, uniformly scaled local AABB, so an ordinary
;; translation or uniform scale does not change an author's plan.
(define (prepare-mesh-correspondence3d source destination
                                       #:vertex-map [explicit-vertices #f]
                                       #:edge-map [explicit-edges #f]
                                       #:face-map [explicit-faces #f]
                                       #:geometric-fallback? [geometric-fallback? #f]
                                       #:geometric-frame [geometric-frame 'local-normalized]
                                       #:geometric-limit [geometric-limit 64]
                                       #:maximum-geometric-cost [maximum-cost #f])
  (unless (mesh3d? source)
    (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" source))
  (unless (mesh3d? destination)
    (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" destination))
  (unless (boolean? geometric-fallback?)
    (raise-argument-error 'prepare-mesh-correspondence3d "boolean?" geometric-fallback?))
  ;; This is deliberately a closed choice.  Adding an authored/world frame
  ;; later must include its affine normal policy in the public contract rather
  ;; than silently changing today's geometric cost.
  (unless (eq? geometric-frame 'local-normalized)
    (raise-argument-error 'prepare-mesh-correspondence3d "'local-normalized"
                          geometric-frame))
  (unless (exact-positive-integer? geometric-limit)
    (raise-argument-error 'prepare-mesh-correspondence3d "exact-positive-integer?"
                          geometric-limit))
  (when (and maximum-cost
             (not (and (finite-real? maximum-cost) (>= maximum-cost 0))))
    (raise-argument-error
     'prepare-mesh-correspondence3d
     "#f or a nonnegative finite real maximum geometric cost"
     maximum-cost))
  (define source-topology (mesh3d-topology source))
  (define destination-topology (mesh3d-topology destination))
  (define same-triangles?
    (equal? (mesh3d-triangles source) (mesh3d-triangles destination)))
  (define same-edges?
    (equal? (mesh3d-edges source) (mesh3d-edges destination)))
  (define vertex-result
    (part-map source destination source-topology destination-topology
              mesh3d-vertices mesh3d-vertex-ids mesh3d-vertex-ids
              explicit-vertices vertex-signature
              (and same-triangles? same-edges?)
              geometric-fallback? geometric-limit maximum-cost
              vertex-geometric-feature))
  (define edge-result
    (part-map source destination source-topology destination-topology
              mesh3d-edges mesh3d-edge-ids mesh3d-edge-ids
              explicit-edges edge-signature
              (and same-triangles? same-edges?)
              geometric-fallback? geometric-limit maximum-cost
              edge-geometric-feature))
  (define face-result
    (part-map source destination source-topology destination-topology
              mesh3d-triangles mesh3d-face-ids mesh3d-face-ids
              explicit-faces face-signature same-triangles?
              geometric-fallback? geometric-limit maximum-cost
              face-geometric-feature))
  (define vertices (part-map-result-map vertex-result))
  (define edges (part-map-result-map edge-result))
  (define faces (part-map-result-map face-result))
  (define all-ambiguities
    (append (vector->list (part-map-result-ambiguities vertex-result))
            (vector->list (part-map-result-ambiguities edge-result))
            (vector->list (part-map-result-ambiguities face-result))))
  (mesh-correspondence3d
   vertices edges faces
   (part-unmatched-hash vertices edges faces)
   (part-destination-unmatched-hash vertices edges faces destination)
   (hasheq
    'vertex-reason (part-map-result-reason vertex-result)
    'edge-reason (part-map-result-reason edge-result)
    'face-reason (part-map-result-reason face-result)
    'vertex-ambiguities (part-map-result-ambiguities vertex-result)
    'edge-ambiguities (part-map-result-ambiguities edge-result)
    'face-ambiguities (part-map-result-ambiguities face-result)
    'vertex-unmatched-signatures (part-map-result-unmatched-signatures vertex-result)
    'edge-unmatched-signatures (part-map-result-unmatched-signatures edge-result)
    'face-unmatched-signatures (part-map-result-unmatched-signatures face-result)
    'ambiguous? (pair? all-ambiguities)
    'geometric-fallback? geometric-fallback?
    'geometric-frame geometric-frame
    'geometric-limit geometric-limit
    'maximum-geometric-cost maximum-cost
    'vertex-geometric-fallback (part-map-result-geometric-diagnostics vertex-result)
    'edge-geometric-fallback (part-map-result-geometric-diagnostics edge-result)
    'face-geometric-fallback (part-map-result-geometric-diagnostics face-result)
    'matched-counts
    (hasheq 'vertex (matched-count vertices)
            'edge (matched-count edges)
            'face (matched-count faces)))))


;;;
;;; Priority handling
;;;

(define (part-map source destination source-topology destination-topology
                  parts source-ids destination-ids explicit signature
                  indexed-topology-identical?
                  geometric-fallback? geometric-limit maximum-cost geometric-feature)
  (define source-count (vector-length (parts source)))
  (define destination-count (vector-length (parts destination)))
  (define source-id-values (source-ids source))
  (define destination-id-values (destination-ids destination))
  (define initial
    (cond
      [explicit
       (define map (checked-explicit-map explicit source-count destination-count))
       (part-map-result map 'explicit #() #() (hasheq 'attempted? #f))]
      [(and source-id-values destination-id-values)
       (define map (semantic-id-map source-id-values destination-id-values))
       (part-map-result map 'semantic-id #() #() (hasheq 'attempted? #f))]
      [(and indexed-topology-identical? (= source-count destination-count))
       (part-map-result (identity-map source-count) 'shared-topology #() #()
                        (hasheq 'attempted? #f))]
      [else
       (signature-map source destination source-topology destination-topology
                      source-count destination-count signature)]))
  (if geometric-fallback?
       (geometric-complete-part-map
       source destination source-topology destination-topology
       source-id-values destination-id-values geometric-feature initial
       geometric-limit maximum-cost)
      initial))

(define (checked-explicit-map explicit source-count destination-count)
  (unless (and (vector? explicit) (= (vector-length explicit) source-count))
    (raise-argument-error
     'prepare-mesh-correspondence3d
     "a source-length vector of destination indexes or #f"
     explicit))
  (define copied
    (for/vector ([destination-index (in-vector explicit)])
      (cond [(not destination-index) #f]
            [(and (exact-nonnegative-integer? destination-index)
                  (< destination-index destination-count))
             destination-index]
            [else
             (raise-argument-error
              'prepare-mesh-correspondence3d
              "an in-range destination index or #f"
              destination-index)])))
  (define duplicate
    (check-duplicates (filter values (vector->list copied))))
  (when duplicate
    (raise-arguments-error
     'prepare-mesh-correspondence3d
     "an injective explicit correspondence"
     "duplicate-destination-index" duplicate))
  (vector->immutable-vector copied))

(define (semantic-id-map source-ids destination-ids)
  (define destination-by-id
    (for/hash ([id (in-vector destination-ids)] [index (in-naturals)])
      (values id index)))
  (vector->immutable-vector
   (for/vector ([id (in-vector source-ids)])
     (hash-ref destination-by-id id #f))))

(define (identity-map count)
  (vector->immutable-vector
   (for/vector ([index (in-range count)]) index)))


;;;
;;; Signature matching
;;;

;; A signature identifies a part only when it occurs once in both meshes.  The
;; report stays in source encounter order, so an author receives the exact
;; indexes that need an explicit map rather than a hash-order-dependent guess.
(define (signature-map source destination source-topology destination-topology
                       source-count destination-count signature)
  (define source-table (signature-table source source-topology source-count signature))
  (define destination-table
    (signature-table destination destination-topology destination-count signature))
  (define mapping (make-vector source-count #f))
  (define ambiguities '())
  (define unmatched-signatures '())
  (define seen (make-hash))
  (for ([index (in-range source-count)])
    (define signature-key (signature source source-topology index))
    (unless (hash-ref seen signature-key #f)
      (hash-set! seen signature-key #t)
      (define source-indices (hash-ref source-table signature-key))
      (define destination-indices (hash-ref destination-table signature-key '()))
      (cond
        [(and (= (length source-indices) 1)
              (= (length destination-indices) 1))
         (vector-set! mapping (car source-indices) (car destination-indices))]
        [(null? destination-indices)
         (set! unmatched-signatures
               (append unmatched-signatures
                       (list (signature-report signature-key source-indices
                                               destination-indices))))]
        [else
         (set! ambiguities
               (append ambiguities
                       (list (signature-report signature-key source-indices
                                               destination-indices))))])))
  (part-map-result
   (vector->immutable-vector mapping)
   'topological-signature
   (vector->immutable-vector (list->vector ambiguities))
   (vector->immutable-vector (list->vector unmatched-signatures))
   (hasheq 'attempted? #f)))

(define (signature-table mesh topology count signature)
  (define table (make-hash))
  (for ([index (in-range count)])
    (define key (signature mesh topology index))
    (hash-set! table key (append (hash-ref table key '()) (list index))))
  table)

(define (signature-report signature source-indices destination-indices)
  (hasheq 'signature signature
          'source-indices
          (vector->immutable-vector (list->vector source-indices))
          'destination-indices
          (vector->immutable-vector (list->vector destination-indices))))


;;;
;;; Conservative local topological signatures
;;;

(define (vertex-signature _mesh topology index)
  (define neighbours (mesh-topology3d-vertex-neighbours topology index))
  (list 'vertex
        (vertex-basic-signature topology index)
        (sort (for/list ([neighbour (in-vector neighbours)])
                (vertex-basic-signature topology neighbour))
              vertex-basic<?)))

(define (vertex-basic-signature topology index)
  (list (vector-length (mesh-topology3d-vertex-neighbours topology index))
        (vector-length (mesh-topology3d-incident-faces topology index))
        (mesh-vertex-topology3d-boundary?
         (vector-ref (mesh-topology3d-vertices topology) index))))

(define (vertex-basic<? left right)
  (cond [(< (first left) (first right)) #t]
        [(> (first left) (first right)) #f]
        [(< (second left) (second right)) #t]
        [(> (second left) (second right)) #f]
        [else (and (not (third left)) (third right))]))

(define (edge-signature mesh topology index)
  (define edge (vector-ref (mesh3d-edges mesh) index))
  (define first-vertex (vector-ref edge 0))
  (define second-vertex (vector-ref edge 1))
  (list 'edge
        (sort (list (vertex-basic-signature topology first-vertex)
                    (vertex-basic-signature topology second-vertex))
              vertex-basic<?)
        (edge-face-count mesh first-vertex second-vertex)))

(define (edge-face-count mesh first-vertex second-vertex)
  (for/sum ([triangle (in-vector (mesh3d-triangles mesh))])
    (if (and (member first-vertex (vector->list triangle))
             (member second-vertex (vector->list triangle)))
        1
        0)))

(define (face-signature _mesh topology index)
  (define face (vector-ref (mesh-topology3d-triangles topology) index))
  (define vertices (mesh-triangle-topology3d-vertices face))
  (define halfedges (mesh-triangle-topology3d-halfedges face))
  (list 'face
        (vector-length vertices)
        (vector-length (mesh-topology3d-face-neighbours topology index))
        (for/sum ([halfedge-index (in-vector halfedges)])
          (if (not (mesh-halfedge3d-opposite
                    (vector-ref (mesh-topology3d-halfedges topology) halfedge-index)))
              1
              0))
        (sort (for/list ([vertex (in-vector vertices)])
                (vertex-basic-signature topology vertex))
              vertex-basic<?)))


;;;
;;; Opt-in geometric completion
;;;

;; Geometric completion is intentionally downstream from all semantic and
;; topological stages.  It only sees unmatched source parts and unused
;; destination parts, so it can never replace an authored identity with a
;; nearby accidental one.

(struct geometric-feature (position normal profile semantic-id) #:transparent)
(struct local-comparison-frame (center scale) #:transparent)

(define (geometric-complete-part-map source destination source-topology destination-topology
                                     source-ids destination-ids feature initial
                                     limit maximum-cost)
  (define initial-map (part-map-result-map initial))
  (define source-candidates
    (for/list ([index (in-range (vector-length initial-map))]
               #:unless (vector-ref initial-map index))
      index))
  (define destination-candidates
    (vector->list
     (unmatched-destination-indices
      initial-map
      (part-count-for-feature destination feature))))
  (define no-attempt
    (hasheq 'attempted? #f
            'initial-reason (part-map-result-reason initial)
            'source-candidates #()
            'destination-candidates #()
            'accepted #()
            'rejected #()))
  (cond
    [(or (null? source-candidates) (null? destination-candidates))
     (part-map-result (part-map-result-map initial)
                      (part-map-result-reason initial)
                      (part-map-result-ambiguities initial)
                      (part-map-result-unmatched-signatures initial)
                      no-attempt)]
    [else
     (when (> (max (length source-candidates) (length destination-candidates)) limit)
       (raise-arguments-error
        'prepare-mesh-correspondence3d
        "an explicit correspondence for a geometric candidate set larger than its declared limit"
        "candidate-count" (vector (length source-candidates) (length destination-candidates))
        "geometric-limit" limit))
     (define source-frame (mesh-local-comparison-frame source))
     (define destination-frame (mesh-local-comparison-frame destination))
     (define source-features
       (for/list ([index (in-list source-candidates)])
         (feature source source-topology source-ids source-frame index)))
     (define destination-features
       (for/list ([index (in-list destination-candidates)])
         (feature destination destination-topology destination-ids destination-frame index)))
     ;; The Hungarian solver is deterministic because its rows and columns are
     ;; source encounter order and every equal-cost pivot selects the lowest
     ;; column index.  It is deliberately bounded above before allocating its
     ;; matrix, not merely after doing expensive work.
     (define assigned
       (minimum-cost-injective-pairs
        (for/vector ([source-feature (in-list source-features)])
          (for/vector ([destination-feature (in-list destination-features)])
            (geometric-feature-cost source-feature destination-feature)))))
     (define completed (vector-copy initial-map))
     (define accepted '())
     (define rejected '())
     (define assigned-source-rows (make-hash))
     (for ([pair (in-list assigned)])
       (define source-row (first pair))
       (define destination-column (second pair))
       (define cost (third pair))
       (hash-set! assigned-source-rows source-row #t)
       (define source-index (list-ref source-candidates source-row))
       (define destination-index (list-ref destination-candidates destination-column))
       (cond [(and maximum-cost (> cost maximum-cost))
              (set! rejected
                    (append rejected
                            (list (hasheq 'source-index source-index
                                          'destination-index destination-index
                                          'cost cost
                                          'reason 'above-maximum-cost))))]
             [else
              (vector-set! completed source-index destination-index)
              (set! accepted
                    (append accepted
                            (list (hasheq 'source-index source-index
                                          'destination-index destination-index
                                          'cost cost))))]))
     ;; A rectangular assignment necessarily leaves source rows unmatched when
     ;; there are fewer destination candidates.  Say why, rather than making
     ;; those omissions look like an algorithmic ambiguity.
     (for ([source-row (in-range (length source-candidates))]
           #:unless (hash-has-key? assigned-source-rows source-row))
       (set! rejected
             (append rejected
                     (list (hasheq 'source-index (list-ref source-candidates source-row)
                                   'destination-index #f
                                   'cost #f
                                   'reason 'no-unused-destination)))))
     (define frozen-map (vector->immutable-vector completed))
     (define accepted-vector (vector->immutable-vector (list->vector accepted)))
     (define report
       (hasheq 'attempted? #t
               'initial-reason (part-map-result-reason initial)
               'source-candidates
               (vector->immutable-vector (list->vector source-candidates))
               'destination-candidates
               (vector->immutable-vector (list->vector destination-candidates))
               'accepted accepted-vector
               'rejected (vector->immutable-vector (list->vector rejected))
               'comparison-frame 'local-normalized))
     (part-map-result
      frozen-map
      (if (positive? (vector-length accepted-vector))
          'geometric-fallback
          (part-map-result-reason initial))
      (unresolved-signature-reports (part-map-result-ambiguities initial) frozen-map)
      (unresolved-signature-reports (part-map-result-unmatched-signatures initial) frozen-map)
      report)]))

;; A feature function is tied to exactly one kind of mesh part.  Use the ID
;; vector, not `mesh3d-*-id`, so absent semantic identities contribute no
;; arbitrary source-index penalty to a geometric comparison.
(define (part-count-for-feature mesh feature)
  (cond [(eq? feature vertex-geometric-feature) (vector-length (mesh3d-vertices mesh))]
        [(eq? feature edge-geometric-feature) (vector-length (mesh3d-edges mesh))]
        [(eq? feature face-geometric-feature) (vector-length (mesh3d-triangles mesh))]
        [else
         (raise-arguments-error
          'prepare-mesh-correspondence3d "a known geometric part feature"
          "feature" feature)]))

(define (mesh-local-comparison-frame mesh)
  (define vertices (mesh3d-vertices mesh))
  (cond [(zero? (vector-length vertices))
         (local-comparison-frame origin3 1)]
        [else
         (define xs (for/list ([point (in-vector vertices)]) (vec3-x point)))
         (define ys (for/list ([point (in-vector vertices)]) (vec3-y point)))
         (define zs (for/list ([point (in-vector vertices)]) (vec3-z point)))
         (define lo (vec3 (apply min xs) (apply min ys) (apply min zs)))
         (define hi (vec3 (apply max xs) (apply max ys) (apply max zs)))
         (define span (vec3- hi lo))
         (local-comparison-frame
          (vec3-scale 1/2 (vec3+ lo hi))
          (max 1 (vec3-x span) (vec3-y span) (vec3-z span)))]))

(define (comparison-point frame point)
  (vec3-scale (/ 1 (local-comparison-frame-scale frame))
              (vec3- point (local-comparison-frame-center frame))))

(define (part-semantic-id ids index)
  (and ids (vector-ref ids index)))

(define (vertex-geometric-feature mesh topology ids frame index)
  (define normals (mesh3d-normals mesh))
  (geometric-feature
   (comparison-point frame (vector-ref (mesh3d-vertices mesh) index))
   (and normals (safe-unit-vector (vector-ref normals index)))
   (list (vector-length (mesh-topology3d-vertex-neighbours topology index))
         (vector-length (mesh-topology3d-incident-faces topology index)))
   (part-semantic-id ids index)))

(define (edge-geometric-feature mesh topology ids frame index)
  (define endpoints (vector-ref (mesh3d-edges mesh) index))
  (define first-index (vector-ref endpoints 0))
  (define second-index (vector-ref endpoints 1))
  (define first (vector-ref (mesh3d-vertices mesh) first-index))
  (define second (vector-ref (mesh3d-vertices mesh) second-index))
  (geometric-feature
   (comparison-point frame (vec3-scale 1/2 (vec3+ first second)))
   ;; Edge direction is intentionally absent from the normal term: reversing
   ;; a declared edge is not a semantic reflection of the adjacent surface.
   #f
   (sort (list (vector-length (mesh-topology3d-vertex-neighbours topology first-index))
               (vector-length (mesh-topology3d-vertex-neighbours topology second-index)))
         <)
   (part-semantic-id ids index)))

(define (face-geometric-feature mesh topology ids frame index)
  (define triangle (vector-ref (mesh3d-triangles mesh) index))
  (define points
    (for/list ([vertex-index (in-vector triangle)])
      (vector-ref (mesh3d-vertices mesh) vertex-index)))
  (geometric-feature
   (comparison-point frame
                     (vec3-scale 1/3
                                 (vec3+ (first points)
                                        (vec3+ (second points) (third points)))))
   (triangle-normal (first points) (second points) (third points))
   (list (vector-length (mesh-topology3d-face-neighbours topology index)))
   (part-semantic-id ids index)))

(define (triangle-normal first second third)
  (safe-unit-vector (vec3-cross (vec3- second first) (vec3- third first))))

(define (safe-unit-vector value)
  (and (positive? (vec3-length value)) (vec3-normalize value)))

(define (geometric-feature-cost source destination)
  (define difference (vec3- (geometric-feature-position source)
                            (geometric-feature-position destination)))
  (define position-cost (vec3-dot difference difference))
  (define normal-cost
    (cond [(and (geometric-feature-normal source)
                (geometric-feature-normal destination))
           ;; This stays within [0,1] even for tiny normalisation roundoff.
           (/ (- 1 (max -1 (min 1
                                 (vec3-dot (geometric-feature-normal source)
                                           (geometric-feature-normal destination)))))
              2)]
          [else 0]))
  ;; Valence is topology evidence, but it is intentionally a soft penalty in
  ;; an explicit geometric fallback.  It cannot prevent an author from
  ;; matching a remeshed shape; the diagnostic still preserves the cost.
  (define profile-cost
    (/ (for/sum ([left (in-list (geometric-feature-profile source))]
                 [right (in-list (geometric-feature-profile destination))])
         (abs (- left right)))
       16))
  (define semantic-penalty
    (if (and (geometric-feature-semantic-id source)
             (geometric-feature-semantic-id destination)
             (not (eq? (geometric-feature-semantic-id source)
                       (geometric-feature-semantic-id destination))))
        1/2
        0))
  (+ position-cost normal-cost profile-cost semantic-penalty))

;; Return (list source-row destination-column cost) values.  The helper
;; reduces a rectangular assignment to the standard rows<=columns Hungarian
;; form and restores source/destination orientation afterwards.
(define (minimum-cost-injective-pairs matrix)
  (define source-count (vector-length matrix))
  (define destination-count
    (if (zero? source-count) 0 (vector-length (vector-ref matrix 0))))
  (cond [(or (zero? source-count) (zero? destination-count)) '()]
        [(<= source-count destination-count)
         (for/list ([destination-column (in-vector (hungarian-row-assignment matrix))]
                    [source-row (in-naturals)])
           (list source-row destination-column
                 (vector-ref (vector-ref matrix source-row) destination-column)))]
        [else
         (define transposed
           (for/vector ([destination-column (in-range destination-count)])
             (for/vector ([source-row (in-range source-count)])
               (vector-ref (vector-ref matrix source-row) destination-column))))
         (for/list ([source-row (in-vector (hungarian-row-assignment transposed))]
                    [destination-column (in-naturals)])
           (list source-row destination-column
                 (vector-ref (vector-ref matrix source-row) destination-column)))]))

;; Standard O(n^3) Hungarian minimisation, with exact/inexact finite costs.
;; Rows must not outnumber columns.  Strict comparisons make source and
;; destination source-order the deterministic tie-break.
(define (hungarian-row-assignment matrix)
  (define rows (vector-length matrix))
  (define columns (vector-length (vector-ref matrix 0)))
  (unless (<= rows columns)
    (raise-arguments-error 'hungarian-row-assignment "rows not exceeding columns"
                           "rows" rows "columns" columns))
  (define u (make-vector (add1 rows) 0))
  (define v (make-vector (add1 columns) 0))
  (define p (make-vector (add1 columns) 0))
  (define way (make-vector (add1 columns) 0))
  (for ([row (in-range 1 (add1 rows))])
    (vector-set! p 0 row)
    (define minimum (make-vector (add1 columns) #f))
    (define used (make-vector (add1 columns) #f))
    (let search ([column 0])
      (vector-set! used column #t)
      (define assigned-row (vector-ref p column))
      (define delta #f)
      (define next-column 0)
      (for ([candidate (in-range 1 (add1 columns))]
            #:unless (vector-ref used candidate))
        (define reduced
          (- (vector-ref (vector-ref matrix (sub1 assigned-row)) (sub1 candidate))
             (vector-ref u assigned-row)
             (vector-ref v candidate)))
        (when (or (not (vector-ref minimum candidate))
                  (< reduced (vector-ref minimum candidate)))
          (vector-set! minimum candidate reduced)
          (vector-set! way candidate column))
        (define candidate-minimum (vector-ref minimum candidate))
        (when (or (not delta) (< candidate-minimum delta))
          (set! delta candidate-minimum)
          (set! next-column candidate)))
      (for ([candidate (in-range 0 (add1 columns))])
        (if (vector-ref used candidate)
            (begin
              (vector-set! u (vector-ref p candidate)
                           (+ (vector-ref u (vector-ref p candidate)) delta))
              (vector-set! v candidate (- (vector-ref v candidate) delta)))
            (when (vector-ref minimum candidate)
              (vector-set! minimum candidate (- (vector-ref minimum candidate) delta)))))
      (if (zero? (vector-ref p next-column))
          (let augment ([current next-column])
            (define previous (vector-ref way current))
            (vector-set! p current (vector-ref p previous))
            (unless (zero? previous) (augment previous)))
          (search next-column))))
  (define assignment (make-vector rows #f))
  (for ([column (in-range 1 (add1 columns))])
    (define row (vector-ref p column))
    (when (positive? row)
      (vector-set! assignment (sub1 row) (sub1 column))))
  (vector->immutable-vector assignment))

;; `signature-report` carries all source indexes with one unresolved local
;; signature.  Once an explicit opt-in cost plan fills those indexes, retain
;; only the entries that still need author intervention.
(define (unresolved-signature-reports reports mapping)
  (vector->immutable-vector
   (for/vector ([report (in-vector reports)]
                #:when (for/or ([index (in-vector (hash-ref report 'source-indices #()))])
                         (not (vector-ref mapping index))))
     report)))


;;;
;;; Diagnostics helpers
;;;

(define (unmatched-indices mapping)
  (vector->immutable-vector
   (for/vector ([index (in-range (vector-length mapping))]
                #:when (not (vector-ref mapping index)))
     index)))

(define (part-unmatched-hash vertices edges faces)
  (hasheq 'vertex (unmatched-indices vertices)
          'edge (unmatched-indices edges)
          'face (unmatched-indices faces)))

(define (part-destination-unmatched-hash vertices edges faces destination)
  (hasheq 'vertex (unmatched-destination-indices
                   vertices (vector-length (mesh3d-vertices destination)))
          'edge (unmatched-destination-indices
                 edges (vector-length (mesh3d-edges destination)))
          'face (unmatched-destination-indices
                 faces (vector-length (mesh3d-triangles destination)))))

(define (unmatched-destination-indices mapping destination-count)
  (define used (make-hash))
  (for ([destination-index (in-vector mapping)] #:when destination-index)
    (hash-set! used destination-index #t))
  (vector->immutable-vector
   (for/vector ([index (in-range destination-count)]
                #:unless (hash-has-key? used index))
     index)))

(define (matched-count mapping)
  (for/sum ([destination-index (in-vector mapping)] #:when destination-index) 1))
