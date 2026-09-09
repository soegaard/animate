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
         (only-in "../color-token.rkt" theme-surface-edge)
         "../geometry.rkt"
         "bounds3.rkt"
         "material3d.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide mesh3d
         mesh3d?
         (struct-out mesh-attribute3d)
         mesh3d-attributes
         mesh3d-attribute
         mesh3d-extra-attributes
         mesh3d-vertices
         mesh3d-triangles
         mesh3d-edges
         mesh3d-vertex-ids
         mesh3d-edge-ids
         mesh3d-face-ids
         mesh3d-vertex-id
         mesh3d-edge-id
         mesh3d-face-id
         mesh3d-normals
         mesh3d-colors
         mesh3d-material
         mesh3d-wireframe-color
         mesh3d-wireframe-width
         mesh3d-local-bounds)


;;;
;;; Mesh Value
;;;

(struct mesh-attribute3d (name values interpolation default semantic?)
  #:transparent
  #:guard
  (lambda (name values interpolation default semantic? who)
    (unless (symbol? name)
      (raise-argument-error who "symbol?" name))
    (unless (vector? values)
      (raise-argument-error who "vector?" values))
    (unless (memq interpolation '(linear normalized-linear source-only))
      (raise-argument-error who
                            "(or/c 'linear 'normalized-linear 'source-only)"
                            interpolation))
    (unless (boolean? semantic?)
      (raise-argument-error who "boolean?" semantic?))
    (when (and semantic? (not (eq? interpolation 'source-only)))
      (raise-arguments-error who
                             "a semantic attribute with 'source-only interpolation"
                             "name" name "interpolation" interpolation))
    (values name
            (vector->immutable-vector
             (for/vector ([value (in-vector values)]) value))
            interpolation default semantic?)))

(struct mesh3d-value
  (id transform opacity vertices triangles edges normals colors
      vertex-ids edge-ids face-ids
      material wireframe-color wireframe-width local-bounds extra-attributes)
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
;;  - vertex-ids       (or/c #f immutable-vectorof symbol?) semantic vertex IDs.
;;  - edge-ids         (or/c #f immutable-vectorof symbol?) semantic edge IDs.
;;  - face-ids         (or/c #f immutable-vectorof symbol?) semantic triangle IDs.
;;  - material         material3d?             surface material.
;;  - wireframe-color  color-spec?             current independent line colour.
;;  - wireframe-width  positive finite real?   current cosmetic line width.
;;  - local-bounds     aabb3?                  enclosure of untransformed vertices.
;;  - extra-attributes immutable descriptors for UV, scalar, and other
;;                     author data not represented by a renderer core field.

(define mesh3d? mesh3d-value?)
(define mesh3d-extra-attributes mesh3d-value-extra-attributes)
(define mesh3d-vertices mesh3d-value-vertices)
(define mesh3d-triangles mesh3d-value-triangles)
(define mesh3d-edges mesh3d-value-edges)
(define mesh3d-vertex-ids mesh3d-value-vertex-ids)
(define mesh3d-edge-ids mesh3d-value-edge-ids)
(define mesh3d-face-ids mesh3d-value-face-ids)
(define mesh3d-normals mesh3d-value-normals)
(define mesh3d-colors mesh3d-value-colors)
(define mesh3d-material mesh3d-value-material)
(define mesh3d-wireframe-color mesh3d-value-wireframe-color)
(define mesh3d-wireframe-width mesh3d-value-wireframe-width)
(define mesh3d-local-bounds mesh3d-value-local-bounds)

;; `mesh3d-attributes` presents the complete vertex-data contract, including
;; the established position/normal/colour/semantic-ID fields and author-added
;; descriptors such as UV or scalar samples.  Core fields remain direct
;; accessors for renderer efficiency; callers that need uniform traversal use
;; this immutable descriptor vector.
(define (mesh3d-attributes mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-attributes "mesh3d?" mesh))
  (define standard
    (append
     (list (mesh-attribute3d 'position (mesh3d-vertices mesh) 'linear #f #f))
     (if (mesh3d-normals mesh)
         (list (mesh-attribute3d 'normal (mesh3d-normals mesh)
                                 'normalized-linear z-axis3 #f))
         '())
     (if (mesh3d-colors mesh)
         (list (mesh-attribute3d 'color (mesh3d-colors mesh)
                                 'linear #f #f))
         '())
     (if (mesh3d-vertex-ids mesh)
         (list (mesh-attribute3d 'semantic-id (mesh3d-vertex-ids mesh)
                                 'source-only #f #t))
         '())))
  (vector->immutable-vector
   (list->vector (append standard (vector->list (mesh3d-extra-attributes mesh))))))

;; mesh3d-attribute : mesh3d? symbol? -> (or/c #f mesh-attribute3d?)
;; Looks up one complete vertex-data descriptor by its stable name.
(define (mesh3d-attribute mesh name)
  (unless (symbol? name)
    (raise-argument-error 'mesh3d-attribute "symbol?" name))
  (for/first ([attribute (in-vector (mesh3d-attributes mesh))]
              #:when (eq? (mesh-attribute3d-name attribute) name))
    attribute))

; mesh3d-vertex-id : mesh3d? exact-nonnegative-integer? -> (or/c symbol? exact-nonnegative-integer?)
;; mesh3d-edge-id : mesh3d? exact-nonnegative-integer? -> (or/c symbol? exact-nonnegative-integer?)
;; mesh3d-face-id : mesh3d? exact-nonnegative-integer? -> (or/c symbol? exact-nonnegative-integer?)
;; Returns an explicit semantic ID when authored, otherwise the stable source
;; index.  Keeping the fallback numeric avoids inventing public symbols merely
;; because a mesh was constructed without semantic-part annotation.
(define (mesh3d-vertex-id mesh index)
  (mesh3d-part-id 'mesh3d-vertex-id mesh index mesh3d-vertex-ids mesh3d-vertices))

(define (mesh3d-edge-id mesh index)
  (mesh3d-part-id 'mesh3d-edge-id mesh index mesh3d-edge-ids mesh3d-edges))

(define (mesh3d-face-id mesh index)
  (mesh3d-part-id 'mesh3d-face-id mesh index mesh3d-face-ids mesh3d-triangles))

(define (mesh3d-part-id who mesh index ids-proc parts-proc)
  (unless (mesh3d? mesh)
    (raise-argument-error who "mesh3d?" mesh))
  (unless (and (exact-nonnegative-integer? index)
               (< index (vector-length (parts-proc mesh))))
    (raise-arguments-error who
                           "an in-range exact nonnegative part index"
                           "index" index
                           "part-count" (vector-length (parts-proc mesh))))
  (define ids (ids-proc mesh))
  (if ids (vector-ref ids index) index))


;;;
;;; Construction
;;;

; mesh3d : #:id symbol? #:vertices (vectorof vec3?)
;          [#:triangles (vectorof index-triple?)]
;          [#:edges (or/c #f (vectorof index-pair?))]
;          [#:vertex-ids (or/c #f (vectorof symbol?))]
;          [#:edge-ids (or/c #f (vectorof symbol?))]
;          [#:face-ids (or/c #f (vectorof symbol?))]
;          [#:normals (or/c #f (vectorof vec3?))]
;          [#:colors (or/c #f (vectorof color-spec?))]
;          [#:attributes (listof mesh-attribute3d?)]
;          [#:material material3d?]
;          [#:transform transform3?] [#:opacity spatial-opacity?]
;          [#:wireframe-color color-spec?] [#:wireframe-width positive-real?]
;          -> mesh3d?
;;   Creates immutable indexed geometry with deterministic triangle and edge order.
(define (mesh3d #:id id
                #:vertices vertices
                #:triangles [triangles #()]
                #:edges [edges #f]
                #:vertex-ids [vertex-ids #f]
                #:edge-ids [edge-ids #f]
                #:face-ids [face-ids #f]
                #:normals [normals #f]
                #:colors [colors #f]
                #:attributes [attributes '()]
                #:material [material default-material3d]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1]
                #:wireframe-color [wireframe-color theme-surface-edge]
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
  (define checked-vertex-ids
    (copy-semantic-id-vector 'mesh3d "vertex IDs" vertex-ids
                             (vector-length checked-vertices)))
  (define checked-edge-ids
    (copy-semantic-id-vector 'mesh3d "edge IDs" edge-ids
                             (vector-length checked-edges)))
  (define checked-face-ids
    (copy-semantic-id-vector 'mesh3d "face IDs" face-ids
                             (vector-length checked-triangles)))
  (define checked-normals
    (copy-attribute-vectors 'mesh3d "normals" normals vec3?
                            (vector-length checked-vertices)))
  (define checked-colors
    (copy-attribute-vectors 'mesh3d "colors" colors color-spec?
                            (vector-length checked-vertices)))
  (define checked-extra-attributes
    (copy-mesh-attributes attributes (vector-length checked-vertices)))
  (mesh3d-value id transform opacity checked-vertices checked-triangles
                checked-edges checked-normals checked-colors
                checked-vertex-ids checked-edge-ids checked-face-ids
                material wireframe-color wireframe-width
                (aabb3-from-points (vector->list checked-vertices))
                checked-extra-attributes))


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

;; Custom descriptors extend rather than shadow the renderer's core position,
;; normal, colour, and semantic-ID channels.  Each descriptor is aligned with
;; the immutable vertex vector before any geometry operation sees the mesh.
(define (copy-mesh-attributes attributes vertex-count)
  (unless (list? attributes)
    (raise-argument-error 'mesh3d "listof mesh-attribute3d?" attributes))
  (define reserved '(position normal color semantic-id))
  (for ([attribute (in-list attributes)])
    (unless (mesh-attribute3d? attribute)
      (raise-argument-error 'mesh3d "mesh-attribute3d?" attribute))
    (when (memq (mesh-attribute3d-name attribute) reserved)
      (raise-arguments-error 'mesh3d
                             "a non-core custom attribute name"
                             "name" (mesh-attribute3d-name attribute)
                             "reserved" reserved))
    (unless (= (vector-length (mesh-attribute3d-values attribute)) vertex-count)
      (raise-arguments-error 'mesh3d
                             "an attribute vector matching vertex count"
                             "name" (mesh-attribute3d-name attribute)
                             "attribute-length"
                             (vector-length (mesh-attribute3d-values attribute))
                             "vertex-count" vertex-count)))
  (define duplicate
    (check-duplicates (map mesh-attribute3d-name attributes)))
  (when duplicate
    (raise-arguments-error 'mesh3d "distinct custom attribute names"
                           "duplicate-name" duplicate))
  (vector->immutable-vector (list->vector attributes)))

; copy-semantic-id-vector : symbol? string? any/c exact-nonnegative-integer?
;                           -> (or/c #f immutable-vectorof symbol?)
;; Semantic IDs are intentionally stricter than generic attributes: a part
;; kind has one unambiguous name per local source index.  Different kinds may
;; reuse a symbol because the accessor's part kind supplies the distinction.
(define (copy-semantic-id-vector who kind values part-count)
  (cond [(not values) #f]
        [(not (vector? values))
         (raise-argument-error who "(or/c #f vector?)" values)]
        [(not (= (vector-length values) part-count))
         (raise-arguments-error who
                                "a semantic ID vector matching its part count"
                                "part-kind" kind
                                "id-count" (vector-length values)
                                "part-count" part-count)]
        [else
         (define copied
           (for/vector ([value (in-vector values)])
             (unless (symbol? value)
               (raise-arguments-error who
                                      "a vector of unique symbol semantic IDs"
                                      "part-kind" kind
                                      "id" value))
             value))
         (define duplicate (check-duplicates (vector->list copied)))
         (when duplicate
           (raise-arguments-error who
                                  "unique semantic IDs within one part kind"
                                  "part-kind" kind
                                  "duplicate-id" duplicate))
         (vector->immutable-vector copied)]))

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
