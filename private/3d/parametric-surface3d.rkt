#lang racket/base

;;;
;;; Immutable Parametric Surfaces
;;;

;; Represents a surface independently from a renderer mesh.  The stored grid,
;; parameter evaluator, normals, and optional scalar-field data make calculus
;; queries and timeline sampling deterministic without retaining frame history.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "bounds3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "surface-mesh3d.rkt"
         "surface-grid.rkt"
         "surface-normal.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide parametric-surface3d
         surface3d?
         surface3d-kind
         surface3d-mesh
         surface3d-local-bounds
         surface3d-diagnostics
         surface3d-provenance
         surface3d-grid
         surface3d-u-range
         surface3d-v-range
         surface3d-resolution
         surface3d-points
         surface3d-normals
         surface3d-unresolved-normal-indices
         surface3d-colors
         surface3d-material
         surface3d-position-at
         surface3d-position-at?
         surface3d-domain-contains?
         surface3d-tangent-u-at
         surface3d-tangent-v-at
         surface3d-normal-at
         surface3d->mesh3d
         surface3d-partial-u
         surface3d-partial-v
         surface3d-interpolate
         surface3d-with-colors
         surface3d-with-material
         surface3d-from-generated-mesh
         surface3d-with-scalar-data
         surface3d-scalar-function
         surface3d-scalar-derivative-x
         surface3d-scalar-derivative-y)


;;;
;;; Data Representation
;;;

(struct scalar-surface-data (function derivative-x derivative-y) #:transparent)

(struct surface3d-value
  (id transform opacity grid evaluator derivative-u derivative-v normals
      unresolved-normal-indices colors material wireframe-color wireframe-width
      scalar-data local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id surface) (surface3d-value-id surface))
   (define (spatial-transform surface) (surface3d-value-transform surface))
   (define (spatial-with-transform surface transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy surface3d-value surface [transform transform]))
   (define (spatial-opacity surface) (surface3d-value-opacity surface))
   (define (spatial-with-opacity surface opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error 'spatial-with-opacity "finite real in [0, 1]" opacity))
     (struct-copy surface3d-value surface [opacity opacity]))
   (define (spatial-local-bounds surface) (surface3d-value-local-bounds surface))])

;; surface3d-value represents a fixed-topology rectangular parametric surface.
;;  - grid        surface-grid? immutable u/v sample positions and topology.
;;  - evaluator   pure (u v -> vec3?) source evaluator for direct calculus.
;;  - normals     immutable-vectorof finite unit vec3? safe for mesh lowering.
;;  - unresolved-normal-indices records sites requiring the fallback normal.
;;  - colors      optional immutable per-vertex opaque semantic colours.
;;  - scalar-data optional height function information for function-surface
;;               calculus helpers; parametric surfaces deliberately omit it.

(struct generated-surface3d-value
  (id transform opacity kind surface-mesh evaluator u-range v-range material
      wireframe-color wireframe-width diagnostics provenance local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id surface) (generated-surface3d-value-id surface))
   (define (spatial-transform surface) (generated-surface3d-value-transform surface))
   (define (spatial-with-transform surface transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy generated-surface3d-value surface [transform transform]))
   (define (spatial-opacity surface) (generated-surface3d-value-opacity surface))
   (define (spatial-with-opacity surface opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error 'spatial-with-opacity "finite real in [0, 1]" opacity))
     (struct-copy generated-surface3d-value surface [opacity opacity]))
   (define (spatial-local-bounds surface)
     (generated-surface3d-value-local-bounds surface))])

;; surface3d is a protocol-shaped union. Regular rectangular surfaces retain
;; their calculus grid; generated adaptive, trimmed, and implicit surfaces
;; carry the common immutable lowering record instead.
(define (surface3d? value)
  (or (surface3d-value? value) (generated-surface3d-value? value)))

(define (surface3d-kind surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-kind "surface3d?" surface))
  (if (surface3d-value? surface)
      'regular-parametric
      (generated-surface3d-value-kind surface)))

(define (surface3d-local-bounds surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-local-bounds "surface3d?" surface))
  (if (surface3d-value? surface)
      (surface3d-value-local-bounds surface)
      (generated-surface3d-value-local-bounds surface)))

(define (surface3d-diagnostics surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-diagnostics "surface3d?" surface))
  (if (surface3d-value? surface)
      (hasheq 'kind 'regular-parametric
              'vertex-count (vector-length (surface3d-points surface))
              'triangle-count (vector-length (surface-grid-triangles (surface3d-grid surface))))
      (generated-surface3d-value-diagnostics surface)))

(define (surface3d-provenance surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-provenance "surface3d?" surface))
  (if (surface3d-value? surface)
      (surface3d-mesh surface)
      (generated-surface3d-value-provenance surface)))
(define (surface3d-grid surface)
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-grid "a regular fixed-grid surface"
                           "surface-kind" (and (surface3d? surface) (surface3d-kind surface))))
  (surface3d-value-grid surface))
(define (surface3d-normals surface)
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-normals "a regular fixed-grid surface"
                           "surface-kind" (and (surface3d? surface) (surface3d-kind surface))))
  (surface3d-value-normals surface))
(define (surface3d-unresolved-normal-indices surface)
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-unresolved-normal-indices "a regular fixed-grid surface"
                           "surface-kind" (and (surface3d? surface) (surface3d-kind surface))))
  (surface3d-value-unresolved-normal-indices surface))
(define (surface3d-colors surface)
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-colors "a regular fixed-grid surface"
                           "surface-kind" (and (surface3d? surface) (surface3d-kind surface))))
  (surface3d-value-colors surface))
(define (surface3d-material surface)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-material "surface3d?" surface))
  (if (surface3d-value? surface)
      (surface3d-value-material surface)
      (generated-surface3d-value-material surface)))


;;;
;;; Construction
;;;

; parametric-surface3d : (finite-real? finite-real? -> vec3?)
;                        #:u-range two-real-range? #:v-range two-real-range?
;                        #:resolution two-exact-integer-resolution? #:id symbol? ...
;                        -> surface3d?
;;   Samples a pure parameterization at one stable rectangular topology.
(define (parametric-surface3d procedure
                              #:u-range [u-range (list -1 1)]
                              #:v-range [v-range (list -1 1)]
                              #:resolution [resolution (list 33 33)]
                              #:id id
                              #:derivative-u [derivative-u #f]
                              #:derivative-v [derivative-v #f]
                              #:material [material (material3d #:color "steelblue" #:shading 'smooth)]
                              #:transform [transform identity-transform3]
                              #:opacity [opacity 1]
                              #:wireframe-color [wireframe-color "steelblue"]
                              #:wireframe-width [wireframe-width 1]
                              #:scalar-data [scalar-data #f])
  (unless (symbol? id) (raise-argument-error 'parametric-surface3d "symbol?" id))
  (unless (procedure? procedure)
    (raise-argument-error 'parametric-surface3d "procedure?" procedure))
  (unless (or (not derivative-u) (procedure? derivative-u))
    (raise-argument-error 'parametric-surface3d "(or/c #f procedure?)" derivative-u))
  (unless (or (not derivative-v) (procedure? derivative-v))
    (raise-argument-error 'parametric-surface3d "(or/c #f procedure?)" derivative-v))
  (unless (material3d? material)
    (raise-argument-error 'parametric-surface3d "material3d?" material))
  (unless (transform3? transform)
    (raise-argument-error 'parametric-surface3d "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'parametric-surface3d "finite real in [0, 1]" opacity))
  (unless (and (finite-real? wireframe-width) (positive? wireframe-width))
    (raise-argument-error 'parametric-surface3d "positive finite wireframe width" wireframe-width))
  (unless (color-spec? wireframe-color)
    (raise-argument-error 'parametric-surface3d "color-spec?" wireframe-color))
  (define grid (make-surface-grid procedure #:u-range u-range #:v-range v-range
                                  #:resolution resolution))
  (surface3d-from-grid id transform opacity grid procedure derivative-u derivative-v
                       material #f wireframe-color wireframe-width scalar-data))


;;;
;;; Public Surface Queries
;;;

; surface3d-u-range : surface3d? -> (list/c finite-real? finite-real?)
;;   Returns the inclusive authored u parameter range.
(define (surface3d-u-range surface)
  (cond [(generated-surface3d-value? surface)
         (define range (generated-surface3d-value-u-range surface))
         (unless range
           (raise-arguments-error 'surface3d-u-range "a parametric surface"
                                  "surface-kind" (surface3d-kind surface)))
         range]
        [else (surface-range surface surface-grid-u-values 'surface3d-u-range)]))

; surface3d-v-range : surface3d? -> (list/c finite-real? finite-real?)
;;   Returns the inclusive authored v parameter range.
(define (surface3d-v-range surface)
  (cond [(generated-surface3d-value? surface)
         (define range (generated-surface3d-value-v-range surface))
         (unless range
           (raise-arguments-error 'surface3d-v-range "a parametric surface"
                                  "surface-kind" (surface3d-kind surface)))
         range]
        [else (surface-range surface surface-grid-v-values 'surface3d-v-range)]))

; surface3d-resolution : surface3d? -> (list/c exact-positive-integer? exact-positive-integer?)
;;   Returns fixed (u v) sample counts.
(define (surface3d-resolution surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-resolution "surface3d?" surface))
  (if (surface3d-value? surface)
      (list (surface-grid-u-count (surface3d-grid surface))
            (surface-grid-v-count (surface3d-grid surface)))
      #f))

; surface3d-points : surface3d? -> immutable-vector?
;;   Returns u-major sampled local positions.
(define (surface3d-points surface)
  (unless (surface3d? surface) (raise-argument-error 'surface3d-points "surface3d?" surface))
  (if (surface3d-value? surface)
      (surface-grid-points (surface3d-grid surface))
      (mesh3d-vertices (surface-mesh3d-mesh
                        (generated-surface3d-value-surface-mesh surface)))))

; surface3d-position-at : surface3d? finite-real? finite-real? -> vec3?
;;   Evaluates the immutable surface's source evaluator within its parameter box.
(define (surface3d-position-at surface u v)
  (cond [(generated-surface3d-value? surface)
         (define evaluator (generated-surface3d-value-evaluator surface))
         (unless evaluator
           (raise-arguments-error 'surface3d-position-at "a parametric surface"
                                  "surface-kind" (surface3d-kind surface)))
         (check-generated-parameter 'surface3d-position-at surface u v)
         (checked-evaluate 'surface3d-position-at evaluator u v)]
        [else
         (check-surface-parameter 'surface3d-position-at surface u v)
         (checked-evaluate 'surface3d-position-at (surface3d-value-evaluator surface) u v)]))

; surface3d-domain-contains? : surface3d? finite-real? finite-real? -> boolean?
;; Reports whether a parametric coordinate belongs to the retained domain.
(define (surface3d-domain-contains? surface u v)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-domain-contains? "surface3d?" surface))
  (unless (and (finite-real? u) (finite-real? v))
    (raise-argument-error 'surface3d-domain-contains? "finite parameter coordinates" (vector u v)))
  (define ranges?
    (with-handlers ([exn:fail? (lambda (_exception) #f)])
      (and (<= (first (surface3d-u-range surface)) u (second (surface3d-u-range surface)))
           (<= (first (surface3d-v-range surface)) v (second (surface3d-v-range surface))))))
  (and ranges?
       (let ([diagnostics (surface3d-diagnostics surface)])
         (define predicate
           (and (hash? diagnostics) (hash-ref diagnostics 'domain-contains? #f)))
         (if predicate (predicate u v) #t))))

; surface3d-position-at? : surface3d? finite-real? finite-real? -> (or/c #f vec3?)
;; Evaluates a parameterization only inside its retained domain.
(define (surface3d-position-at? surface u v)
  (and (surface3d-domain-contains? surface u v)
       (surface3d-position-at surface u v)))

; surface3d-tangent-u-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns a finite nonzero u tangent using analytic data or fixed finite differences.
(define (surface3d-tangent-u-at surface u v)
  (when (generated-surface3d-value? surface)
    (raise-arguments-error 'surface3d-tangent-u-at "a regular surface with tangent data"
                           "surface-kind" (surface3d-kind surface)))
  (check-surface-parameter 'surface3d-tangent-u-at surface u v)
  (or (and (surface3d-value-derivative-u surface)
           (checked-evaluate 'surface3d-tangent-u-at
                             (surface3d-value-derivative-u surface) u v))
      (surface-finite-tangent surface u v 'u)))

; surface3d-tangent-v-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns a finite nonzero v tangent using analytic data or fixed finite differences.
(define (surface3d-tangent-v-at surface u v)
  (when (generated-surface3d-value? surface)
    (raise-arguments-error 'surface3d-tangent-v-at "a regular surface with tangent data"
                           "surface-kind" (surface3d-kind surface)))
  (check-surface-parameter 'surface3d-tangent-v-at surface u v)
  (or (and (surface3d-value-derivative-v surface)
           (checked-evaluate 'surface3d-tangent-v-at
                             (surface3d-value-derivative-v surface) u v))
      (surface-finite-tangent surface u v 'v)))

; surface3d-normal-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns the normalized u-cross-v normal, falling back to a sampled normal.
(define (surface3d-normal-at surface u v)
  (when (generated-surface3d-value? surface)
    (raise-arguments-error 'surface3d-normal-at "a regular surface with tangent data"
                           "surface-kind" (surface3d-kind surface)))
  (define candidate
    (vec3-cross (surface3d-tangent-u-at surface u v)
                (surface3d-tangent-v-at surface u v)))
  (if (zero? (vec3-length candidate))
      (nearest-grid-normal surface u v)
      (vec3-normalize candidate)))

; surface3d-scalar-function : surface3d? -> (or/c #f procedure?)
;;   Returns a function-surface height procedure, if one was declared.
(define (surface3d-scalar-function surface)
  (surface-scalar-field surface scalar-surface-data-function))

; surface3d-scalar-derivative-x : surface3d? -> (or/c #f procedure?)
;;   Returns the declared partial-x height derivative when available.
(define (surface3d-scalar-derivative-x surface)
  (surface-scalar-field surface scalar-surface-data-derivative-x))

; surface3d-scalar-derivative-y : surface3d? -> (or/c #f procedure?)
;;   Returns the declared partial-y height derivative when available.
(define (surface3d-scalar-derivative-y surface)
  (surface-scalar-field surface scalar-surface-data-derivative-y))


;;;
;;; Mesh Lowering and Immutable Updates
;;;

; surface3d->mesh3d : surface3d? -> mesh3d?
;;   Lowers stable surface samples to an indexed opaque renderer mesh.
(define (surface3d->mesh3d surface)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d->mesh3d "surface3d?" surface))
  (cond [(surface3d-value? surface)
         (mesh3d #:id (spatial-id surface)
                 #:vertices (surface3d-points surface)
                 #:triangles (surface-grid-triangles (surface3d-grid surface))
                 #:normals (surface3d-normals surface)
                 #:colors (surface3d-colors surface)
                 #:material (surface3d-material surface)
                 #:transform (spatial-transform surface)
                 #:opacity (spatial-opacity surface)
                 #:wireframe-color (surface3d-value-wireframe-color surface)
                 #:wireframe-width (surface3d-value-wireframe-width surface))]
        [else (surface-mesh3d-mesh (generated-surface3d-value-surface-mesh surface))]))

; surface3d-mesh : surface3d? -> surface-mesh3d?
;; Returns renderer geometry together with topology and sample provenance.
(define (surface3d-mesh surface)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-mesh "surface3d?" surface))
  (cond [(generated-surface3d-value? surface)
         (generated-surface3d-value-surface-mesh surface)]
        [else
         (define grid (surface3d-grid surface))
         (surface-mesh3d
          (surface3d->mesh3d surface)
          (for*/vector ([u (in-vector (surface-grid-u-values grid))]
                        [u-index (in-naturals)]
                        [v (in-vector (surface-grid-v-values grid))]
                        [v-index (in-naturals)])
            (hasheq 'kind 'regular-grid 'u u 'v v
                    'u-index u-index 'v-index v-index))
          ;; A second construction gives every point/triangle a stable simple
          ;; provenance record without changing the historic grid API.
          (for/vector ([triangle (in-vector (surface-grid-triangles grid))]
                       [index (in-naturals)])
            (hasheq 'triangle index 'kind 'regular-grid))
          (vector 'regular-grid (surface-grid-u-values grid) (surface-grid-v-values grid)
                  (surface-grid-triangles grid))
          (surface3d-diagnostics surface))]))

; surface3d-with-colors : surface3d? (or/c #f vector?) -> surface3d?
;;   Replaces optional immutable per-vertex RGBA colour data.
(define (surface3d-with-colors surface colors)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-with-colors "surface3d?" surface))
  (define checked
    (check-colors 'surface3d-with-colors colors
                  (vector-length (surface3d-points surface))))
  (cond [(surface3d-value? surface)
         (struct-copy surface3d-value surface [colors checked])]
        [else
         (struct-copy
          generated-surface3d-value surface
          [surface-mesh
           (surface-mesh-with-style
            (generated-surface3d-value-surface-mesh surface)
            (spatial-id surface) (surface3d-material surface) checked
            (generated-surface3d-value-wireframe-color surface)
            (generated-surface3d-value-wireframe-width surface))])]))

; surface3d-with-material : surface3d? material3d? -> surface3d?
;;   Returns the same topology and samples with a replacement surface material.
(define (surface3d-with-material surface material)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-with-material "surface3d?" surface))
  (unless (material3d? material)
    (raise-argument-error 'surface3d-with-material "material3d?" material))
  (cond [(surface3d-value? surface)
         (struct-copy surface3d-value surface [material material])]
        [else
         (struct-copy
          generated-surface3d-value surface
          [material material]
          [surface-mesh
           (surface-mesh-with-style
            (generated-surface3d-value-surface-mesh surface)
            (spatial-id surface) material
            (mesh3d-colors
             (surface-mesh3d-mesh (generated-surface3d-value-surface-mesh surface)))
            (generated-surface3d-value-wireframe-color surface)
            (generated-surface3d-value-wireframe-width surface))])]))

; surface3d-with-scalar-data : surface3d? procedure? ... -> surface3d?
;;   Attaches function-surface height metadata without changing sampled geometry.
(define (surface3d-with-scalar-data surface function derivative-x derivative-y)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-with-scalar-data "surface3d?" surface))
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-with-scalar-data "a regular function surface"
                           "surface-kind" (surface3d-kind surface)))
  (for ([value (in-list (list function derivative-x derivative-y))]
        [name (in-list '(function derivative-x derivative-y))])
    (unless (or (not value) (procedure? value))
      (raise-arguments-error 'surface3d-with-scalar-data
                             "a procedure or #f"
                             "field" name "value" value)))
  (unless (procedure? function)
    (raise-argument-error 'surface3d-with-scalar-data "procedure?" function))
  (struct-copy surface3d-value surface
               [scalar-data (scalar-surface-data function derivative-x derivative-y)]))

; surface3d-partial-u : surface3d? unit-real? -> surface3d?
;;   Directly samples the source surface over its leading u fraction, retaining
;; the original grid resolution and triangle identities at every timeline time.
(define (surface3d-partial-u surface progress)
  (surface3d-partial surface progress 'u))

; surface3d-partial-v : surface3d? unit-real? -> surface3d?
;;   Directly samples the source surface over its leading v fraction.
(define (surface3d-partial-v surface progress)
  (surface3d-partial surface progress 'v))

; surface3d-interpolate : surface3d? surface3d? unit-real? -> surface3d?
;;   Morphs equal-resolution, equal-domain surfaces by direct vertex sampling.
(define (surface3d-interpolate source destination progress)
  (unless (surface3d? source) (raise-argument-error 'surface3d-interpolate "surface3d?" source))
  (unless (surface3d? destination) (raise-argument-error 'surface3d-interpolate "surface3d?" destination))
  (check-progress 'surface3d-interpolate progress)
  (unless (and (surface3d-value? source) (surface3d-value? destination))
    (raise-arguments-error
     'surface3d-interpolate
     "two regular parametric surfaces with equal fixed topology; use an explicit cross-fade for generated surfaces"
     "source-kind" (surface3d-kind source)
     "destination-kind" (surface3d-kind destination)))
  (check-compatible-surfaces 'surface3d-interpolate source destination)
  (cond [(zero? progress) source]
        [(= progress 1)
         ;; Preserve the source target identity for path-stable replacement.
         (struct-copy surface3d-value destination [id (spatial-id source)])]
        [else
         (define grid
           (surface-grid-from-points
            (surface-grid-u-values (surface3d-grid source))
            (surface-grid-v-values (surface3d-grid source))
            (interpolated-rows source destination progress)))
         (define material
           (interpolate-material (surface3d-material source)
                                 (surface3d-material destination) progress))
         (surface3d-from-grid
          (spatial-id source) (spatial-transform source) (spatial-opacity source)
          grid (grid-evaluator grid) #f #f material
          (interpolate-colors source destination progress)
          (surface3d-value-wireframe-color source)
          (surface3d-value-wireframe-width source)
          #f)]))


;;;
;;; Internal Constructors
;;;

; surface3d-from-generated-mesh : symbol? symbol? surface-mesh3d? ... -> surface3d?
;; Constructs an immutable non-grid surface value lowered by an adaptive,
;; trimmed, or implicit producer. It is public to the focused producer modules
;; but is not an author-facing mesh escape hatch.
(define (surface3d-from-generated-mesh kind id surface-mesh
                                       #:transform [transform identity-transform3]
                                       #:opacity [opacity 1]
                                       #:material [material (mesh3d-material
                                                             (surface-mesh3d-mesh surface-mesh))]
                                       #:wireframe-color [wireframe-color "steelblue"]
                                       #:wireframe-width [wireframe-width 1]
                                       #:evaluator [evaluator #f]
                                       #:u-range [u-range #f]
                                       #:v-range [v-range #f]
                                       #:diagnostics [diagnostics (surface-mesh3d-diagnostics surface-mesh)]
                                       #:provenance [provenance surface-mesh])
  (unless (symbol? kind)
    (raise-argument-error 'surface3d-from-generated-mesh "symbol?" kind))
  (unless (symbol? id)
    (raise-argument-error 'surface3d-from-generated-mesh "symbol?" id))
  (unless (surface-mesh3d? surface-mesh)
    (raise-argument-error 'surface3d-from-generated-mesh "surface-mesh3d?" surface-mesh))
  (unless (transform3? transform)
    (raise-argument-error 'surface3d-from-generated-mesh "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'surface3d-from-generated-mesh "finite real in [0, 1]" opacity))
  (unless (material3d? material)
    (raise-argument-error 'surface3d-from-generated-mesh "material3d?" material))
  (unless (and (finite-real? wireframe-width) (positive? wireframe-width))
    (raise-argument-error 'surface3d-from-generated-mesh "positive finite wireframe width"
                          wireframe-width))
  (unless (color-spec? wireframe-color)
    (raise-argument-error 'surface3d-from-generated-mesh "color-spec?" wireframe-color))
  (unless (or (not evaluator) (procedure? evaluator))
    (raise-argument-error 'surface3d-from-generated-mesh "(or/c #f procedure?)" evaluator))
  (define styled
    (surface-mesh-with-style surface-mesh id material
                             (mesh3d-colors (surface-mesh3d-mesh surface-mesh))
                             wireframe-color wireframe-width))
  (generated-surface3d-value
   id transform opacity kind styled evaluator u-range v-range material
   wireframe-color wireframe-width diagnostics provenance
   (mesh3d-local-bounds (surface-mesh3d-mesh styled))))

(define (surface-mesh-with-style source id material colors wireframe-color wireframe-width)
  (define old (surface-mesh3d-mesh source))
  (surface-mesh3d
   (mesh3d #:id id
           #:vertices (mesh3d-vertices old)
           #:triangles (mesh3d-triangles old)
           #:edges (mesh3d-edges old)
           #:normals (mesh3d-normals old)
           #:colors colors
           #:material material
           #:wireframe-color wireframe-color
           #:wireframe-width wireframe-width)
   (surface-mesh3d-vertex-provenance source)
   (surface-mesh3d-triangle-provenance source)
   (surface-mesh3d-topology-key source)
   (surface-mesh3d-diagnostics source)))

(define (surface3d-from-grid id transform opacity grid evaluator derivative-u derivative-v
                             material colors wireframe-color wireframe-width scalar-data)
  (define-values (normals unresolved)
    (surface-grid-vertex-normals grid #:derivative-u derivative-u #:derivative-v derivative-v))
  (surface3d-value id transform opacity grid evaluator derivative-u derivative-v normals
                   unresolved (check-colors 'surface3d-from-grid colors
                                            (vector-length (surface-grid-points grid)))
                   material wireframe-color wireframe-width scalar-data
                   (aabb3-from-points (vector->list (surface-grid-points grid)))))

(define (surface3d-partial surface progress axis)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-partial "surface3d?" surface))
  (unless (surface3d-value? surface)
    (raise-arguments-error 'surface3d-partial
                           "a regular parametric surface; generated surfaces require an explicit reveal strategy"
                           "surface-kind" (surface3d-kind surface)))
  (check-progress 'surface3d-partial progress)
  (define u-range (surface3d-u-range surface))
  (define v-range (surface3d-v-range surface))
  (define remapped-evaluator
    (lambda (u v)
      (define mapped-u
        (if (eq? axis 'u)
            (+ (first u-range) (* progress (- u (first u-range))))
            u))
      (define mapped-v
        (if (eq? axis 'v)
            (+ (first v-range) (* progress (- v (first v-range))))
            v))
      (checked-evaluate 'surface3d-partial (surface3d-value-evaluator surface)
                        mapped-u mapped-v)))
  (define grid
    ;; Keep the source parameter lattice unchanged.  At progress zero every
    ;; sampled position is coincident, so all retained triangles degenerate
    ;; deterministically instead of changing topology or identity.
    (make-surface-grid remapped-evaluator
                       #:u-range u-range #:v-range v-range
                       #:resolution (surface3d-resolution surface)))
  (surface3d-from-grid
   (spatial-id surface) (spatial-transform surface) (spatial-opacity surface)
   grid remapped-evaluator #f #f (surface3d-material surface) #f
   (surface3d-value-wireframe-color surface)
   (surface3d-value-wireframe-width surface)
   (surface3d-value-scalar-data surface)))

(define (surface-range surface selector who)
  (unless (surface3d? surface) (raise-argument-error who "surface3d?" surface))
  (define values (selector (surface3d-grid surface)))
  (list (vector-ref values 0) (vector-ref values (sub1 (vector-length values)))))

(define (surface-scalar-field surface accessor)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-scalar-function "surface3d?" surface))
  (define data (and (surface3d-value? surface) (surface3d-value-scalar-data surface)))
  (and data (accessor data)))

(define (check-generated-parameter who surface u v)
  (unless (and (finite-real? u) (finite-real? v))
    (raise-argument-error who "finite u and v parameters" (vector u v)))
  (define u-range (generated-surface3d-value-u-range surface))
  (define v-range (generated-surface3d-value-v-range surface))
  (unless (and u-range v-range
               (<= (first u-range) u (second u-range))
               (<= (first v-range) v (second v-range)))
    (raise-arguments-error who "parameters inside the generated surface domain"
                           "u" u "v" v "u-range" u-range "v-range" v-range)))

(define (check-colors who colors expected-count)
  (cond [(not colors) #f]
        [(not (and (vector? colors) (= (vector-length colors) expected-count)))
         (raise-arguments-error who "a color vector matching the surface vertex count"
                                "colors" colors "vertex-count" expected-count)]
        [else
         (vector->immutable-vector
          (for/vector ([color (in-vector colors)])
            (unless (and (color-spec? color)
                         (= (rgba-color-alpha (color-spec->rgba-color color who)) 1))
              (raise-argument-error who "opaque color-spec?" color))
            (color-spec->rgba-color color who)))]))

(define (checked-evaluate who procedure u v)
  (define point (procedure u v))
  (unless (and (vec3? point) (vec3-finite? point))
    (raise-arguments-error who "a finite vec3? surface result"
                           "u" u "v" v "result" point))
  point)

(define (check-surface-parameter who surface u v)
  (unless (surface3d? surface) (raise-argument-error who "surface3d?" surface))
  (unless (finite-real? u) (raise-argument-error who "finite-real?" u))
  (unless (finite-real? v) (raise-argument-error who "finite-real?" v))
  (define u-range (surface3d-u-range surface))
  (define v-range (surface3d-v-range surface))
  (unless (<= (first u-range) u (second u-range))
    (raise-arguments-error who "u inside the authored surface range" "u" u "u-range" u-range))
  (unless (<= (first v-range) v (second v-range))
    (raise-arguments-error who "v inside the authored surface range" "v" v "v-range" v-range)))

(define (surface-finite-tangent surface u v axis)
  (define range (if (eq? axis 'u) (surface3d-u-range surface) (surface3d-v-range surface)))
  (define count (if (eq? axis 'u) (first (surface3d-resolution surface))
                    (second (surface3d-resolution surface))))
  (define step (/ (- (second range) (first range)) (sub1 count)))
  (define low (max (first range) (- (if (eq? axis 'u) u v) step)))
  (define high (min (second range) (+ (if (eq? axis 'u) u v) step)))
  (define (evaluate parameter)
    (if (eq? axis 'u) (surface3d-position-at surface parameter v)
        (surface3d-position-at surface u parameter)))
  (define tangent (vec3- (evaluate high) (evaluate low)))
  (if (zero? (vec3-length tangent))
      origin3
      tangent))

(define (nearest-grid-normal surface u v)
  (define grid (surface3d-grid surface))
  (define (nearest values value)
    (for/fold ([best-index 0] [best-distance +inf.0])
              ([candidate (in-vector values)] [index (in-naturals)])
      (define distance (abs (- candidate value)))
      (if (< distance best-distance) (values index distance) (values best-index best-distance))))
  (define-values (u-index _u-distance) (nearest (surface-grid-u-values grid) u))
  (define-values (v-index _v-distance) (nearest (surface-grid-v-values grid) v))
  (vector-ref (surface3d-normals surface) (surface-grid-index grid u-index v-index)))

(define (grid-evaluator grid)
  ;; A bilinear evaluator is used only by derived partial/morph surfaces.  The
  ;; original parametric surface retains its supplied evaluator exactly.
  (lambda (u v)
    (bilinear-grid-point grid u v)))

(define (bilinear-grid-point grid u v)
  (define-values (u-low u-high u-progress) (bracket-parameter (surface-grid-u-values grid) u))
  (define-values (v-low v-high v-progress) (bracket-parameter (surface-grid-v-values grid) v))
  (define lower (vec3-lerp (surface-grid-ref grid u-low v-low)
                           (surface-grid-ref grid u-high v-low) u-progress))
  (define upper (vec3-lerp (surface-grid-ref grid u-low v-high)
                           (surface-grid-ref grid u-high v-high) u-progress))
  (vec3-lerp lower upper v-progress))

(define (bracket-parameter values value)
  (define last-index (sub1 (vector-length values)))
  (cond [(<= value (vector-ref values 0)) (values 0 0 0)]
        [(>= value (vector-ref values last-index)) (values last-index last-index 0)]
        [else
         (define high
           (for/first ([candidate (in-range 1 (add1 last-index))]
                       #:when (<= value (vector-ref values candidate)))
             candidate))
         (define low (sub1 high))
         (define first-value (vector-ref values low))
         (define second-value (vector-ref values high))
         (values low high (/ (- value first-value) (- second-value first-value)))]))

(define (check-progress who progress)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error who "finite real in [0, 1]" progress)))

(define (check-compatible-surfaces who source destination)
  (unless (equal? (surface3d-resolution source) (surface3d-resolution destination))
    (raise-arguments-error who "surfaces with equal grid resolution"
                           "source-resolution" (surface3d-resolution source)
                           "destination-resolution" (surface3d-resolution destination)))
  (unless (and (equal? (surface3d-u-range source) (surface3d-u-range destination))
               (equal? (surface3d-v-range source) (surface3d-v-range destination)))
    (raise-arguments-error who "surfaces with equal parameter domains"
                           "source-u-range" (surface3d-u-range source)
                           "destination-u-range" (surface3d-u-range destination)))
  (unless (compatible-materials? (surface3d-material source) (surface3d-material destination))
    (raise-arguments-error who "surfaces with compatible material structure"
                           "source-material" (surface3d-material source)
                           "destination-material" (surface3d-material destination))))

(define (compatible-materials? source destination)
  (and (eq? (material3d-shading source) (material3d-shading destination))
       (= (material3d-ambient source) (material3d-ambient destination))
       (= (material3d-diffuse source) (material3d-diffuse destination))
       (= (material3d-specular source) (material3d-specular destination))
       (= (material3d-roughness source) (material3d-roughness destination))
       (eq? (material3d-double-sided? source) (material3d-double-sided? destination))
       (eq? (material3d-wireframe? source) (material3d-wireframe? destination))))

(define (interpolated-rows source destination progress)
  (define u-count (first (surface3d-resolution source)))
  (define v-count (second (surface3d-resolution source)))
  (for/vector ([u-index (in-range u-count)])
    (for/vector ([v-index (in-range v-count)])
      (define index (+ (* u-index v-count) v-index))
      (vec3-lerp (vector-ref (surface3d-points source) index)
                 (vector-ref (surface3d-points destination) index)
                 progress))))

(define (interpolate-material source destination progress)
  (material3d #:color (rgba-color-lerp (material3d-color source)
                                        (material3d-color destination) progress)
              #:shading (material3d-shading source)
              #:ambient (material3d-ambient source)
              #:diffuse (material3d-diffuse source)
              #:specular (material3d-specular source)
              #:roughness (material3d-roughness source)
              #:double-sided? (material3d-double-sided? source)
              #:wireframe? (material3d-wireframe? source)))

(define (interpolate-colors source destination progress)
  (define source-colors (surface3d-colors source))
  (define destination-colors (surface3d-colors destination))
  (cond [(and (not source-colors) (not destination-colors)) #f]
        [(and source-colors destination-colors)
         (vector->immutable-vector
          (for/vector ([source-color (in-vector source-colors)]
                       [destination-color (in-vector destination-colors)])
            (rgba-color-lerp source-color destination-color progress)))]
        [else
         (raise-arguments-error 'surface3d-interpolate
                                "both surfaces either with or without per-vertex colors"
                                "source-colors" source-colors
                                "destination-colors" destination-colors)]))
