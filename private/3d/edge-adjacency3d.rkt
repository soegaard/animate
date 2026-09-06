#lang racket/base

;;;
;;; Stable Indexed-Mesh Edge Adjacency
;;;

;; Builds the purely combinatorial edge table used by topology diagnostics,
;; feature-edge extraction, and compiled geometry.  Hash tables only support
;; lookup while constructing the table; all observable order follows triangle
;; index and then local-edge index.


;;;
;;; Imports and Exports
;;;

(require "mesh3d.rkt")

(provide (struct-out edge-incidence3d)
         (struct-out edge-adjacency3d)
         mesh3d-edge-adjacency)


;;;
;;; Immutable Edge Records
;;;

(struct edge-incidence3d
  (triangle-index local-edge-index from-index to-index)
  #:transparent)

;; edge-incidence3d records one directed triangle side in declared face order.

(struct edge-adjacency3d (edge incidences)
  #:transparent)

;; edge-adjacency3d represents one canonical undirected edge.
;;  - edge        immutable vector of its increasing vertex indices.
;;  - incidences  immutable vector of directed edge-incidence3d values.


;;;
;;; Construction
;;;

; mesh3d-edge-adjacency : mesh3d? -> immutable-vectorof edge-adjacency3d?
;;   Returns unique triangle edges in first directed-incidence encounter order.
(define (mesh3d-edge-adjacency mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-edge-adjacency "mesh3d?" mesh))
  ;; `order` supplies the observable order.  The mutable vectors collect only
  ;; the incidences belonging to one already ordered key.
  (define entries-by-key (make-hash))
  (define key-order '())
  (for ([triangle (in-vector (mesh3d-triangles mesh))]
        [triangle-index (in-naturals)])
    (define indices
      (vector (vector-ref triangle 0)
              (vector-ref triangle 1)
              (vector-ref triangle 2)))
    (for ([local-edge-index (in-range 3)])
      (define from-index (vector-ref indices local-edge-index))
      (define to-index (vector-ref indices (modulo (add1 local-edge-index) 3)))
      (define key (cons (min from-index to-index) (max from-index to-index)))
      (unless (hash-has-key? entries-by-key key)
        (hash-set! entries-by-key key '())
        (set! key-order (append key-order (list key))))
      (hash-set! entries-by-key key
                 (append (hash-ref entries-by-key key)
                         (list (edge-incidence3d triangle-index local-edge-index
                                                 from-index to-index))))))
  (vector->immutable-vector
   (list->vector
    (for/list ([key (in-list key-order)])
      (edge-adjacency3d
       (vector-immutable (car key) (cdr key))
       (vector->immutable-vector
        (list->vector (hash-ref entries-by-key key))))))))
