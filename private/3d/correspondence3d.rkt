#lang racket/base

;;;
;;; Conservative Mesh Correspondence Planning
;;;

;; A correspondence is a source-index -> destination-index plan, not an
;; animation.  The plan must explain a match before any geometry moves.  In
;; particular, a symmetric local signature is never promoted to an arbitrary
;; graph-isomorphism claim.

(require racket/list
         "mesh3d.rkt"
         "mesh-topology3d.rkt")

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

(struct part-map-result (map reason ambiguities unmatched-signatures)
  #:transparent)


;;;
;;; Public planner
;;;

; prepare-mesh-correspondence3d
; : mesh3d? mesh3d?
;   [#:vertex-map (or/c #f vector?)]
;   [#:edge-map (or/c #f vector?)]
;   [#:face-map (or/c #f vector?)]
;   -> mesh-correspondence3d?
;;
;; Priority is explicit author map, shared semantic IDs, identical indexed
;; topology, then a unique local topological signature.  Geometric matching is
;; intentionally a later opt-in layer: proximity must never be the default for
;; a symmetric mesh with several plausible correspondences.
(define (prepare-mesh-correspondence3d source destination
                                       #:vertex-map [explicit-vertices #f]
                                       #:edge-map [explicit-edges #f]
                                       #:face-map [explicit-faces #f])
  (unless (mesh3d? source)
    (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" source))
  (unless (mesh3d? destination)
    (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" destination))
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
              (and same-triangles? same-edges?)))
  (define edge-result
    (part-map source destination source-topology destination-topology
              mesh3d-edges mesh3d-edge-ids mesh3d-edge-ids
              explicit-edges edge-signature
              (and same-triangles? same-edges?)))
  (define face-result
    (part-map source destination source-topology destination-topology
              mesh3d-triangles mesh3d-face-ids mesh3d-face-ids
              explicit-faces face-signature same-triangles?))
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
    'geometric-fallback? #f
    'matched-counts
    (hasheq 'vertex (matched-count vertices)
            'edge (matched-count edges)
            'face (matched-count faces)))))


;;;
;;; Priority handling
;;;

(define (part-map source destination source-topology destination-topology
                  parts source-ids destination-ids explicit signature
                  indexed-topology-identical?)
  (define source-count (vector-length (parts source)))
  (define destination-count (vector-length (parts destination)))
  (cond
    [explicit
     (define map (checked-explicit-map explicit source-count destination-count))
     (part-map-result map 'explicit #() #())]
    [(and (source-ids source) (destination-ids destination))
     (define map (semantic-id-map (source-ids source) (destination-ids destination)))
     (part-map-result map 'semantic-id #() #())]
    [(and indexed-topology-identical? (= source-count destination-count))
     (part-map-result (identity-map source-count) 'shared-topology #() #())]
    [else
     (signature-map source destination source-topology destination-topology
                    source-count destination-count signature)]))

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
   (vector->immutable-vector (list->vector unmatched-signatures))))

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
