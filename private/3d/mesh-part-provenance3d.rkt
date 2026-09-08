#lang racket/base

;;;
;;; Immutable Part Provenance for Topology-Changing Mesh Operations
;;;

;; A mesh operation can preserve an authored part, merge several parts into
;; one, split it, derive a different-dimensional counterpart, generate a new
;; part, or discard it.  This module records those facts without conflating a
;; missing semantic ID with a generated numeric index.

(require racket/list)

(provide (struct-out mesh-part-reference3d)
         (struct-out mesh-part-provenance-entry3d)
         (struct-out mesh-part-provenance3d)
         make-mesh-part-provenance3d
         mesh-part-provenance3d-source-results
         mesh-part-provenance3d-result-sources)

(define part-kinds '(vertex edge face))
(define provenance-relations
  '(preserved merged split generated discarded ambiguous derived))

;; A reference deliberately carries a part kind because duals legitimately map
;; source faces to result vertices and source vertices to result faces.
(struct mesh-part-reference3d (kind id)
  #:transparent
  #:guard
  (lambda (kind id who)
    (unless (memq kind part-kinds)
      (raise-argument-error who "one of 'vertex, 'edge, or 'face" kind))
    (values kind id)))

;; One source part and zero or more result parts.  A `generated` entry has no
;; source part; a `discarded` entry has no result parts.  The result vector is
;; immutable and preserves the operation's deterministic output order.
(struct mesh-part-provenance-entry3d (source-part result-parts relation)
  #:transparent
  #:guard
  (lambda (source-part result-parts relation who)
    (unless (or (not source-part) (mesh-part-reference3d? source-part))
      (raise-argument-error who "#f or mesh-part-reference3d?" source-part))
    (unless (and (vector? result-parts)
                 (for/and ([part (in-vector result-parts)])
                   (mesh-part-reference3d? part)))
      (raise-argument-error who "vector of mesh-part-reference3d values" result-parts))
    (unless (memq relation provenance-relations)
      (raise-argument-error who
                            "one of 'preserved, 'merged, 'split, 'generated, 'discarded, 'ambiguous, or 'derived"
                            relation))
    (when (and (eq? relation 'generated) source-part)
      (raise-arguments-error who "a generated part without a source part"
                             "source-part" source-part))
    (when (and (eq? relation 'discarded) (positive? (vector-length result-parts)))
      (raise-arguments-error who "a discarded part without result parts"
                             "result-parts" result-parts))
    (values source-part
            (vector->immutable-vector
             (for/vector ([part (in-vector result-parts)]) part))
            relation)))

;; The three vectors are grouped by source part kind, and warnings name
;; intentionally lossy/ambiguous operation facts rather than hiding them.
(struct mesh-part-provenance3d (vertices edges faces warnings)
  #:transparent
  #:guard
  (lambda (vertices edges faces warnings who)
    (for ([entries (in-list (list vertices edges faces))]
          [name (in-list '(vertices edges faces))])
      (unless (and (vector? entries)
                   (for/and ([entry (in-vector entries)])
                     (mesh-part-provenance-entry3d? entry)))
        (raise-argument-error who
                              (format "vector of provenance entries for ~a" name)
                              entries)))
    (unless (vector? warnings)
      (raise-argument-error who "vector? for warnings" warnings))
    (values (immutable-entry-vector vertices)
            (immutable-entry-vector edges)
            (immutable-entry-vector faces)
            (vector->immutable-vector
             (for/vector ([warning (in-vector warnings)]) warning)))))

(define (immutable-entry-vector entries)
  (vector->immutable-vector
   (for/vector ([entry (in-vector entries)]) entry)))

(define (make-mesh-part-provenance3d
         #:vertices [vertices #()]
         #:edges [edges #()]
         #:faces [faces #()]
         #:warnings [warnings #()])
  (mesh-part-provenance3d vertices edges faces warnings))

;; Query helpers are deliberately multimap-shaped.  Multiple entries may name
;; one result after a merge, and a split's one source can name many results.
(define (mesh-part-provenance3d-source-results provenance source-part)
  (check-provenance 'mesh-part-provenance3d-source-results provenance)
  (check-reference 'mesh-part-provenance3d-source-results source-part)
  (for/first ([entry (in-vector (entries-for-kind provenance
                                                  (mesh-part-reference3d-kind source-part)))]
              #:when (equal? (mesh-part-provenance-entry3d-source-part entry)
                             source-part))
    (mesh-part-provenance-entry3d-result-parts entry)))

(define (mesh-part-provenance3d-result-sources provenance result-part)
  (check-provenance 'mesh-part-provenance3d-result-sources provenance)
  (check-reference 'mesh-part-provenance3d-result-sources result-part)
  (vector->immutable-vector
   (list->vector
    (for*/list ([entries (in-list (list (mesh-part-provenance3d-vertices provenance)
                                        (mesh-part-provenance3d-edges provenance)
                                        (mesh-part-provenance3d-faces provenance)))]
                [entry (in-vector entries)]
                #:when (and (mesh-part-provenance-entry3d-source-part entry)
                            (for/or ([part (in-vector (mesh-part-provenance-entry3d-result-parts entry))])
                              (equal? part result-part))))
      (mesh-part-provenance-entry3d-source-part entry)))))

(define (entries-for-kind provenance kind)
  (case kind
    [(vertex) (mesh-part-provenance3d-vertices provenance)]
    [(edge) (mesh-part-provenance3d-edges provenance)]
    [(face) (mesh-part-provenance3d-faces provenance)]))

(define (check-provenance who provenance)
  (unless (mesh-part-provenance3d? provenance)
    (raise-argument-error who "mesh-part-provenance3d?" provenance)))

(define (check-reference who reference)
  (unless (mesh-part-reference3d? reference)
    (raise-argument-error who "mesh-part-reference3d?" reference)))
