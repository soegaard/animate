#lang racket/base

;;;
;;; Explicit Mesh Orientation Repair
;;;

;; This module keeps orientation repair separate from `mesh3d` construction.
;; A mesh remains an inexpensive immutable value; callers opt in to analysing,
;; repairing, and accepting a replacement value.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "bounds3.rkt"
         "mesh-analysis3d.rkt"
         "mesh3d.rkt"
         "spatial-visual.rkt"
         "vec3.rkt")

(provide (struct-out mesh3d-orientation-report)
         mesh3d-orient-consistently
         mesh3d-orient-outward
         mesh3d-self-intersection-candidates)


;;;
;;; Immutable Reports
;;;

(struct mesh3d-orientation-report
  (initial-analysis final-analysis flipped-triangle-indices outward?)
  #:transparent)

;; mesh3d-orientation-report states exactly what the repair changed.  It does
;; not claim that per-vertex normal attributes have been regenerated: those
;; attributes are authored data, and rebuilding them is a distinct operation.


;;;
;;; Orientation Repair
;;;

; mesh3d-orient-consistently : mesh3d?
;                              -> (values mesh3d? mesh3d-orientation-report?)
;;   Returns a new mesh whose manifold face adjacencies have opposed winding.
;;   Raises an explicit error when topology cannot be oriented unambiguously.
(define (mesh3d-orient-consistently mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-orient-consistently "mesh3d?" mesh))
  (define initial (analyze-mesh3d mesh))
  (ensure-orientable-input 'mesh3d-orient-consistently initial)
  (define-values (parities conflict?) (mesh3d-orientation-parities mesh))
  (when conflict?
    (raise-arguments-error 'mesh3d-orient-consistently
                           "an orientable mesh"
                           "reason" "the face-adjacency parity graph conflicts"))
  (define flipped
    (vector->immutable-vector
     (for/vector ([parity (in-vector parities)] [index (in-naturals)]
                  #:when (= parity 1))
       index)))
  (define repaired (mesh-with-triangle-flips mesh flipped))
  (define final (analyze-mesh3d repaired))
  (values repaired
          (mesh3d-orientation-report initial final flipped #f)))

; mesh3d-orient-outward : mesh3d?
;                         -> (values mesh3d? mesh3d-orientation-report?)
;;   Consistently orients each closed component and makes positive-volume
;;   components outward-facing.  Open, non-manifold, non-orientable, and
;;   zero-volume inputs fail rather than silently receiving a guessed outside.
(define (mesh3d-orient-outward mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-orient-outward "mesh3d?" mesh))
  (define initial (analyze-mesh3d mesh))
  (unless (mesh3d-analysis-watertight? initial)
    (raise-arguments-error 'mesh3d-orient-outward
                           "a watertight mesh"
                           "boundary-edge-count"
                           (vector-length (mesh3d-analysis-boundary-edges initial))
                           "nonmanifold-edge-count"
                           (vector-length (mesh3d-analysis-nonmanifold-edges initial))
                           "degenerate-triangle-count"
                           (vector-length (mesh3d-analysis-degenerate-triangles initial))))
  (define-values (consistently-oriented consistent-report)
    (mesh3d-orient-consistently mesh))
  (define consistent-analysis (mesh3d-orientation-report-final-analysis consistent-report))
  (unless (mesh3d-analysis-orientable? consistent-analysis)
    (raise-arguments-error 'mesh3d-orient-outward
                           "an orientable mesh"
                           "reason" "the face-adjacency parity graph conflicts"))
  (define tolerance (mesh-volume-tolerance consistently-oriented))
  (define outward-flips
    (for/fold ([indices '()])
              ([component (in-vector (mesh3d-analysis-connected-components consistent-analysis))]
               [volume (in-vector (mesh3d-analysis-signed-component-volumes consistent-analysis))])
      (when (<= (abs volume) tolerance)
        (raise-arguments-error 'mesh3d-orient-outward
                               "a closed component with nonzero signed volume"
                               "signed-volume" volume
                               "tolerance" tolerance))
      (if (negative? volume)
          (append indices (vector->list component))
          indices)))
  (define flipped
    (vector->immutable-vector (list->vector (sort outward-flips <))))
  (define repaired (mesh-with-triangle-flips consistently-oriented flipped))
  (define final (analyze-mesh3d repaired))
  (values repaired
          (mesh3d-orientation-report
           initial final
           (flipped-index-xor
            (mesh3d-orientation-report-flipped-triangle-indices consistent-report)
            outward-flips)
           #t)))

(define (ensure-orientable-input who analysis)
  (when (positive? (vector-length (mesh3d-analysis-degenerate-triangles analysis)))
    (raise-arguments-error who
                           "a mesh without degenerate triangles"
                           "degenerate-triangle-count"
                           (vector-length (mesh3d-analysis-degenerate-triangles analysis))))
  (when (positive? (vector-length (mesh3d-analysis-nonmanifold-edges analysis)))
    (raise-arguments-error who
                           "a mesh without non-manifold edges"
                           "nonmanifold-edge-count"
                           (vector-length (mesh3d-analysis-nonmanifold-edges analysis))))
  (unless (mesh3d-analysis-orientable? analysis)
    (raise-arguments-error who
                           "an orientable mesh"
                           "reason" "the face-adjacency parity graph conflicts")))

(define (mesh-with-triangle-flips mesh flipped-indices)
  (define flip? (make-hash))
  (for ([index (in-vector flipped-indices)])
    (hash-set! flip? index #t))
  (mesh3d
   #:id (spatial-id mesh)
   #:vertices (mesh3d-vertices mesh)
   #:triangles
   (vector->immutable-vector
    (for/vector ([triangle (in-vector (mesh3d-triangles mesh))]
                 [index (in-naturals)])
      (if (hash-has-key? flip? index)
          (vector-immutable (vector-ref triangle 0)
                            (vector-ref triangle 2)
                            (vector-ref triangle 1))
          triangle)))
   #:edges (mesh3d-edges mesh)
   #:normals (mesh3d-normals mesh)
   #:colors (mesh3d-colors mesh)
   #:material (mesh3d-material mesh)
   #:transform (spatial-transform mesh)
   #:opacity (spatial-opacity mesh)
   #:wireframe-color (mesh3d-wireframe-color mesh)
   #:wireframe-width (mesh3d-wireframe-width mesh)))

(define (mesh-volume-tolerance mesh)
  (define bounds (mesh3d-local-bounds mesh))
  (if (aabb3-empty? bounds)
      0
      (let ([extent (vec3-length (aabb3-size bounds))])
        (max 1e-45 (* 1e-12 extent extent extent)))))

(define (flipped-index-xor first-indices second-indices)
  (define parity (make-hash))
  (for ([index (in-list (append (vector->list first-indices) second-indices))])
    (hash-set! parity index (not (hash-ref parity index #f))))
  (vector->immutable-vector
   (list->vector
    (sort (for/list ([(index flipped?) (in-hash parity)] #:when flipped?) index) <))))


;;;
;;; Broad-phase Self-intersection Candidates
;;;

; mesh3d-self-intersection-candidates : mesh3d?
;                                       -> immutable-vectorof index-pair?
;;   Returns deterministic, conservative triangle pairs whose local AABBs
;;   overlap.  It intentionally does not claim narrow-phase intersection.
(define (mesh3d-self-intersection-candidates mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-self-intersection-candidates "mesh3d?" mesh))
  (define triangles (mesh3d-triangles mesh))
  (define boxes
    (for/vector ([triangle (in-vector triangles)])
      (triangle-bounds mesh triangle)))
  (vector->immutable-vector
   (for*/vector ([first-index (in-range (vector-length triangles))]
                 [second-index (in-range (add1 first-index)
                                         (vector-length triangles))]
                 #:unless (triangles-share-vertex?
                            (vector-ref triangles first-index)
                            (vector-ref triangles second-index))
                 #:when (aabb3-overlap? (vector-ref boxes first-index)
                                        (vector-ref boxes second-index)))
     (vector-immutable first-index second-index))))

(define (triangle-bounds mesh triangle)
  (aabb3-from-points
   (for/list ([index (in-vector triangle)])
     (vector-ref (mesh3d-vertices mesh) index))))

(define (triangles-share-vertex? first second)
  (for/or ([first-index (in-vector first)])
    (for/or ([second-index (in-vector second)])
      (= first-index second-index))))

(define (aabb3-overlap? first second)
  (and (<= (vec3-x (aabb3-minimum first)) (vec3-x (aabb3-maximum second)))
       (<= (vec3-x (aabb3-minimum second)) (vec3-x (aabb3-maximum first)))
       (<= (vec3-y (aabb3-minimum first)) (vec3-y (aabb3-maximum second)))
       (<= (vec3-y (aabb3-minimum second)) (vec3-y (aabb3-maximum first)))
       (<= (vec3-z (aabb3-minimum first)) (vec3-z (aabb3-maximum second)))
       (<= (vec3-z (aabb3-minimum second)) (vec3-z (aabb3-maximum first)))))
