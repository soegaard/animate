#lang racket/base

;;;
;;; Spatial Mesh Values
;;;

;; Defines immutable indexed mesh geometry.  SCENE-3D-B uses only its stable
;; edge order for wireframes; triangle, normal, and colour data are retained
;; now so later opaque renderers do not need a second mesh representation.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "bounds3.rkt"
         "material3d.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide mesh3d
         mesh3d?
         mesh3d-vertices
         mesh3d-triangles
         mesh3d-edges
         mesh3d-normals
         mesh3d-colors
         mesh3d-material
         mesh3d-wireframe-color
         mesh3d-wireframe-width
         mesh3d-local-bounds)


;;;
;;; Mesh Value
;;;

(struct mesh3d-value
  (id transform opacity vertices triangles edges normals colors
      material wireframe-color wireframe-width local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id mesh)
     (mesh3d-value-id mesh))
   (define (spatial-transform mesh)
     (mesh3d-value-transform mesh))
   (define (spatial-with-transform mesh transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy mesh3d-value mesh [transform transform]))
   (define (spatial-opacity mesh)
     (mesh3d-value-opacity mesh))
   (define (spatial-with-opacity mesh opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error
        'spatial-with-opacity "finite real in the closed unit interval" opacity))
     (struct-copy mesh3d-value mesh [opacity opacity]))
   (define (spatial-local-bounds mesh)
     (mesh3d-value-local-bounds mesh))])

;; mesh3d-value represents indexed local geometry.
;;  - id               symbol?                 stable spatial identity.
;;  - transform        transform3?             local object placement.
;;  - opacity          spatial-opacity?        inherited wireframe opacity.
;;  - vertices         immutable-vectorof vec3? stable vertex order.
;;  - triangles        immutable-vectorof index triples, stable face order.
;;  - edges            immutable-vectorof index pairs, stable line order.
;;  - normals          (or/c #f immutable-vectorof vec3?) per-vertex normals.
;;  - colors           (or/c #f immutable-vectorof color-spec?) per-vertex colors.
;;  - material         material3d?             surface material.
;;  - wireframe-color  color-spec?             current independent line colour.
;;  - wireframe-width  positive finite real?   current cosmetic line width.
;;  - local-bounds     aabb3?                  enclosure of untransformed vertices.

(define mesh3d? mesh3d-value?)
(define mesh3d-vertices mesh3d-value-vertices)
(define mesh3d-triangles mesh3d-value-triangles)
(define mesh3d-edges mesh3d-value-edges)
(define mesh3d-normals mesh3d-value-normals)
(define mesh3d-colors mesh3d-value-colors)
(define mesh3d-material mesh3d-value-material)
(define mesh3d-wireframe-color mesh3d-value-wireframe-color)
(define mesh3d-wireframe-width mesh3d-value-wireframe-width)
(define mesh3d-local-bounds mesh3d-value-local-bounds)


;;;
;;; Construction
;;;

; mesh3d : #:id symbol? #:vertices (vectorof vec3?)
;          [#:triangles (vectorof index-triple?)]
;          [#:edges (or/c #f (vectorof index-pair?))]
;          [#:normals (or/c #f (vectorof vec3?))]
;          [#:colors (or/c #f (vectorof color-spec?))]
;          [#:material material3d?]
;          [#:transform transform3?] [#:opacity spatial-opacity?]
;          [#:wireframe-color color-spec?] [#:wireframe-width positive-real?]
;          -> mesh3d?
;;   Creates immutable indexed geometry with deterministic triangle and edge order.
(define (mesh3d #:id id
                #:vertices vertices
                #:triangles [triangles #()]
                #:edges [edges #f]
                #:normals [normals #f]
                #:colors [colors #f]
                #:material [material default-material3d]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1]
                #:wireframe-color [wireframe-color "steelblue"]
                #:wireframe-width [wireframe-width 2])
  (unless (symbol? id)
    (raise-argument-error 'mesh3d "symbol?" id))
  (unless (transform3? transform)
    (raise-argument-error 'mesh3d "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'mesh3d "finite real in the closed unit interval" opacity))
  (unless (and (finite-real? wireframe-width) (positive? wireframe-width))
    (raise-argument-error 'mesh3d "positive finite real?" wireframe-width))
  (unless (color-spec? wireframe-color)
    (raise-argument-error 'mesh3d "color-spec?" wireframe-color))
  (unless (material3d? material)
    (raise-argument-error 'mesh3d "material3d?" material))
  (define checked-vertices (copy-vertices vertices))
  (define checked-triangles
    (copy-index-tuples 'mesh3d "triangle index triples" triangles 3
                       (vector-length checked-vertices)))
  (define checked-edges
    (if edges
        (copy-index-tuples 'mesh3d "edge index pairs" edges 2
                           (vector-length checked-vertices))
        (derive-edges checked-triangles)))
  (define checked-normals
    (copy-attribute-vectors 'mesh3d "normals" normals vec3?
                            (vector-length checked-vertices)))
  (define checked-colors
    (copy-attribute-vectors 'mesh3d "colors" colors color-spec?
                            (vector-length checked-vertices)))
  (mesh3d-value id transform opacity checked-vertices checked-triangles
                checked-edges checked-normals checked-colors material wireframe-color
                wireframe-width (aabb3-from-points (vector->list checked-vertices))))


;;;
;;; Immutable Input Normalization
;;;

; copy-vertices : any/c -> (immutable-vectorof vec3?)
;;   Validates and freezes vertex input without retaining a mutable vector.
(define (copy-vertices vertices)
  (unless (vector? vertices)
    (raise-argument-error 'mesh3d "vector?" vertices))
  (vector->immutable-vector
   (for/vector ([vertex (in-vector vertices)])
     (unless (vec3? vertex)
       (raise-argument-error 'mesh3d "vector of vec3?" vertices))
     vertex)))

; copy-index-tuples : symbol? string? any/c exact-positive-integer?
;                     exact-nonnegative-integer? -> immutable-vector?
;;   Validates fixed-size in-range immutable index tuples.
(define (copy-index-tuples who kind tuples arity vertex-count)
  (unless (vector? tuples)
    (raise-argument-error who "vector?" tuples))
  (vector->immutable-vector
   (for/vector ([tuple (in-vector tuples)])
     (unless (and (vector? tuple) (= (vector-length tuple) arity))
       (raise-arguments-error who
                              (format "a vector of ~a" kind)
                              "tuple" tuple))
     (define indices
       (for/list ([index (in-vector tuple)])
         (unless (and (exact-nonnegative-integer? index)
                      (< index vertex-count))
           (raise-arguments-error who
                                  "an in-range exact nonnegative vertex index"
                                  "index" index
                                  "vertex-count" vertex-count))
         index))
     (when (not (= (length (remove-duplicates indices)) arity))
       (raise-arguments-error who
                              "an index tuple without repeated vertices"
                              "tuple" tuple))
     (apply vector-immutable indices))))

; copy-attribute-vectors : symbol? string? any/c procedure?
;                           exact-nonnegative-integer? -> (or/c #f immutable-vector?)
;;   Validates an optional per-vertex attribute vector and freezes its container.
(define (copy-attribute-vectors who kind values predicate vertex-count)
  (cond [(not values) #f]
        [(not (vector? values))
         (raise-argument-error who "(or/c #f vector?)" values)]
        [(not (= (vector-length values) vertex-count))
         (raise-arguments-error who
                                "an attribute vector matching vertex count"
                                "attribute" kind
                                "attribute-length" (vector-length values)
                                "vertex-count" vertex-count)]
        [else
         (vector->immutable-vector
          (for/vector ([value (in-vector values)])
            (unless (predicate value)
              (raise-arguments-error who
                                     "a compatible attribute vector"
                                     "attribute" kind
                                     "value" value))
            value))]))

; derive-edges : immutable-vectorof triangle-index-triple? -> immutable-vectorof edge-index-pair?
;;   Returns each undirected triangle edge once in first-face encounter order.
(define (derive-edges triangles)
  (define seen (make-hash))
  (define reversed '())
  (for ([triangle (in-vector triangles)])
    (define index0 (vector-ref triangle 0))
    (define index1 (vector-ref triangle 1))
    (define index2 (vector-ref triangle 2))
    (for ([edge (in-list (list (list index0 index1)
                               (list index1 index2)
                               (list index2 index0)))])
      (define low (min (first edge) (second edge)))
      (define high (max (first edge) (second edge)))
      (define key (cons low high))
      (unless (hash-has-key? seen key)
        (hash-set! seen key #t)
        (set! reversed (cons (vector-immutable low high) reversed)))))
  (vector->immutable-vector (list->vector (reverse reversed))))
