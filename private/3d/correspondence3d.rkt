#lang racket/base
(require "mesh3d.rkt")
(provide (struct-out spatial-correspondence3d) (struct-out mesh-correspondence3d)
         prepare-mesh-correspondence3d)
(struct spatial-correspondence3d (source destination reason mode route diagnostics) #:transparent)
(struct mesh-correspondence3d (vertex-map edge-map face-map unmatched-source unmatched-destination diagnostics) #:transparent)

;; Produces source-index -> destination-index mappings. Explicit maps outrank
;; semantic IDs, which outrank equal indexed topology. Ambiguity is retained in
;; diagnostics; no geometric nearest-neighbour guess is made by default.
(define (prepare-mesh-correspondence3d source destination
                                       #:vertex-map [explicit-vertices #f]
                                       #:edge-map [explicit-edges #f]
                                       #:face-map [explicit-faces #f])
 (unless (mesh3d? source) (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" source))
 (unless (mesh3d? destination) (raise-argument-error 'prepare-mesh-correspondence3d "mesh3d?" destination))
 (define-values (vm vr) (part-map source destination mesh3d-vertices mesh3d-vertices mesh3d-vertex-ids mesh3d-vertex-ids explicit-vertices))
 (define-values (em er) (part-map source destination mesh3d-edges mesh3d-edges mesh3d-edge-ids mesh3d-edge-ids explicit-edges))
 (define-values (fm fr) (part-map source destination mesh3d-triangles mesh3d-triangles mesh3d-face-ids mesh3d-face-ids explicit-faces))
 (mesh-correspondence3d vm em fm
  (vector->immutable-vector (list->vector (for/list ([i (in-range (vector-length vm))] #:when (not (vector-ref vm i))) i)))
  (vector->immutable-vector (list->vector (for/list ([i (in-range (vector-length (mesh3d-vertices destination)))] #:unless (member i (filter values (vector->list vm)))) i)))
  (hasheq 'vertex-reason vr 'edge-reason er 'face-reason fr 'ambiguous? #f)))

(define (part-map src dst src-parts dst-parts src-ids dst-ids explicit)
 (define n (vector-length (src-parts src))) (define m (vector-length (dst-parts dst)))
 (cond [explicit
  (unless (and (vector? explicit) (= (vector-length explicit) n)) (raise-argument-error 'prepare-mesh-correspondence3d "source-length mapping vector" explicit))
  (values (vector->immutable-vector (for/vector ([x (in-vector explicit)]) (and x (begin (unless (and (exact-nonnegative-integer? x) (< x m)) (raise-argument-error 'prepare-mesh-correspondence3d "destination index or #f" x)) x)))) 'explicit)]
 [(and (src-ids src) (dst-ids dst))
  (define table (for/hash ([id (in-vector (dst-ids dst))] [i (in-naturals)]) (values id i)))
  (values (vector->immutable-vector (for/vector ([id (in-vector (src-ids src))]) (hash-ref table id #f))) 'semantic-id)]
 [(= n m) (values (vector->immutable-vector (for/vector ([i (in-range n)]) i)) 'shared-index)]
 [else (values (vector->immutable-vector (make-vector n #f)) 'unmatched)]))
