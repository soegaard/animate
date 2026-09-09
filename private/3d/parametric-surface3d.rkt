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

(require racket/generic
         racket/list
         "../color-style.rkt"
         (only-in "../color-token.rkt" theme-surface theme-surface-edge)
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
         gen:surface3d
         surface3d?
         surface3d-kind
         surface3d-local-mesh
         surface3d-domain
         surface3d-evaluate
         surface3d-frame-at
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
         surface3d-scalar-derivative-y
         (struct-out surface-domain3d)
         (struct-out surface-diagnostics3d)
         (struct-out surface-frame3d))


;;;
;;; Data Representation
;;;

(struct scalar-surface-data (function derivative-x derivative-y) #:transparent)

;; A surface domain owns the executable membership predicate.  Diagnostics
;; therefore remain ordinary serializable data, suitable for snapshots and
;; cache records, rather than accidentally carrying a closure from an authored
;; trim field.
(struct surface-domain3d (u-range v-range contains? cache-key)
  #:transparent)

;; `fields` is immutable descriptive data (usually a hash or a focused report
;; structure); it must not contain the procedural `contains?` hook above.
(struct surface-diagnostics3d (kind fields)
  #:transparent)

;; A retained local frame is the common answer for both regular and generated
;; parametric surfaces.  Implicit surfaces, which have no UV evaluator, reject
;; this query truthfully.
(struct surface-frame3d (point tangent-u tangent-v normal)
  #:transparent)

;; This is the actual surface protocol.  New surface producers can implement
;; it without joining a hand-maintained union in this module.
(define-generics surface3d
  (surface3d-kind surface3d)
  (surface3d-local-mesh surface3d)
  (surface3d-local-bounds surface3d)
  (surface3d-diagnostics surface3d)
  (surface3d-provenance surface3d)
  (surface3d-domain surface3d)
  (surface3d-evaluate surface3d u v)
  (surface3d-frame-at surface3d u v))

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
   (define (spatial-local-bounds surface) (surface3d-value-local-bounds surface))]
  #:methods gen:surface3d
  [(define (surface3d-kind _surface) 'regular-parametric)
   (define (surface3d-local-mesh surface)
     (surface3d-value->local-mesh surface))
   (define (surface3d-local-bounds surface)
     (surface3d-value-local-bounds surface))
   (define (surface3d-diagnostics surface)
     (surface-diagnostics3d
      'regular-parametric
      (hasheq 'kind 'regular-parametric
              'vertex-count (vector-length (surface3d-value-normals surface))
              'triangle-count (vector-length
                               (surface-grid-triangles (surface3d-value-grid surface))))))
   (define (surface3d-provenance surface) (surface3d-local-mesh surface))
   (define (surface3d-domain surface)
     (surface-domain3d
      (surface-range surface surface-grid-u-values 'surface3d-domain)
      (surface-range surface surface-grid-v-values 'surface3d-domain)
      #f
      (vector 'regular-domain
              (surface-grid-u-values (surface3d-value-grid surface))
              (surface-grid-v-values (surface3d-value-grid surface)))))
   (define (surface3d-evaluate surface u v)
     (check-surface-parameter 'surface3d-evaluate surface u v)
     (checked-evaluate 'surface3d-evaluate (surface3d-value-evaluator surface) u v))
   (define (surface3d-frame-at surface u v)
     (surface-frame-from-surface surface u v))])

;; surface3d-value represents a fixed-topology rectangular parametric surface.
;;  - grid        surface-grid? immutable u/v sample positions and topology.
;;  - evaluator   pure (u v -> vec3?) source evaluator for direct calculus.
;;  - normals     immutable-vectorof finite unit vec3? safe for mesh lowering.
;;  - unresolved-normal-indices records sites requiring the fallback normal.
;;  - colors      optional immutable per-vertex opaque semantic colours.
;;  - scalar-data optional height function information for function-surface
;;               calculus helpers; parametric surfaces deliberately omit it.

(struct generated-surface3d-value
  (id transform opacity kind surface-mesh evaluator u-range v-range domain material
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
     (generated-surface3d-value-local-bounds surface))]
  #:methods gen:surface3d
  [(define (surface3d-kind surface) (generated-surface3d-value-kind surface))
   (define (surface3d-local-mesh surface)
     (generated-surface3d-value-surface-mesh surface))
   (define (surface3d-local-bounds surface)
     (generated-surface3d-value-local-bounds surface))
   (define (surface3d-diagnostics surface)
     (surface-diagnostics3d
      (generated-surface3d-value-kind surface)
      (generated-surface3d-value-diagnostics surface)))
   (define (surface3d-provenance surface)
     (generated-surface3d-value-provenance surface))
   (define (surface3d-domain surface)
     (generated-surface3d-value-domain surface))
   (define (surface3d-evaluate surface u v)
     (define evaluator (generated-surface3d-value-evaluator surface))
     (unless evaluator
       (raise-arguments-error 'surface3d-evaluate "a parametric surface"
                              "surface-kind" (surface3d-kind surface)))
     (check-generated-parameter 'surface3d-evaluate surface u v)
     (checked-evaluate 'surface3d-evaluate evaluator u v))
   (define (surface3d-frame-at surface u v)
     (unless (generated-surface3d-value-evaluator surface)
       (raise-arguments-error 'surface3d-frame-at
                              "a generated parametric surface with a retained evaluator"
                              "surface-kind" (surface3d-kind surface)))
     (surface-frame-from-surface surface u v))])
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
                              #:material [material (material3d #:color theme-surface #:shading 'smooth)]
                              #:transform [transform identity-transform3]
                              #:opacity [opacity 1]
                              #:wireframe-color [wireframe-color theme-surface-edge]
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
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-position-at "surface3d?" surface))
  (surface3d-evaluate surface u v))

; surface3d-domain-contains? : surface3d? finite-real? finite-real? -> boolean?
;; Reports whether a parametric coordinate belongs to the retained domain.
(define (surface3d-domain-contains? surface u v)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-domain-contains? "surface3d?" surface))
  (unless (and (finite-real? u) (finite-real? v))
    (raise-argument-error 'surface3d-domain-contains? "finite parameter coordinates" (vector u v)))
  (define domain (surface3d-domain surface))
  (and domain
       (<= (first (surface-domain3d-u-range domain)) u
           (second (surface-domain3d-u-range domain)))
       (<= (first (surface-domain3d-v-range domain)) v
           (second (surface-domain3d-v-range domain)))
       (let ([contains? (surface-domain3d-contains? domain)])
         (or (not contains?) (contains? u v)))))

; surface3d-position-at? : surface3d? finite-real? finite-real? -> (or/c #f vec3?)
;; Evaluates a parameterization only inside its retained domain.
(define (surface3d-position-at? surface u v)
  (and (surface3d-domain-contains? surface u v)
       (surface3d-position-at surface u v)))

; surface3d-tangent-u-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns a finite nonzero u tangent using analytic data or fixed finite differences.
(define (surface3d-tangent-u-at surface u v)
  (cond [(generated-surface3d-value? surface)
         (unless (generated-surface3d-value-evaluator surface)
           (raise-arguments-error 'surface3d-tangent-u-at "a generated parametric surface"
                                  "surface-kind" (surface3d-kind surface)))
         (check-generated-parameter 'surface3d-tangent-u-at surface u v)
         (surface-finite-tangent surface u v 'u)]
        [else
         (check-surface-parameter 'surface3d-tangent-u-at surface u v)
         (or (and (surface3d-value-derivative-u surface)
                  (checked-evaluate 'surface3d-tangent-u-at
                                    (surface3d-value-derivative-u surface) u v))
             (surface-finite-tangent surface u v 'u))]))

; surface3d-tangent-v-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns a finite nonzero v tangent using analytic data or fixed finite differences.
(define (surface3d-tangent-v-at surface u v)
  (cond [(generated-surface3d-value? surface)
         (unless (generated-surface3d-value-evaluator surface)
           (raise-arguments-error 'surface3d-tangent-v-at "a generated parametric surface"
                                  "surface-kind" (surface3d-kind surface)))
         (check-generated-parameter 'surface3d-tangent-v-at surface u v)
         (surface-finite-tangent surface u v 'v)]
        [else
         (check-surface-parameter 'surface3d-tangent-v-at surface u v)
         (or (and (surface3d-value-derivative-v surface)
                  (checked-evaluate 'surface3d-tangent-v-at
                                    (surface3d-value-derivative-v surface) u v))
             (surface-finite-tangent surface u v 'v))]))

; surface3d-normal-at : surface3d? finite-real? finite-real? -> vec3?
;;   Returns the normalized u-cross-v normal, falling back to a sampled normal.
(define (surface3d-normal-at surface u v)
  (define candidate
    (vec3-cross (surface3d-tangent-u-at surface u v)
                (surface3d-tangent-v-at surface u v)))
  (if (zero? (vec3-length candidate))
      (if (generated-surface3d-value? surface)
          (raise-arguments-error 'surface3d-normal-at
                                 "a generated parameterization with a non-degenerate local frame"
                                 "surface-kind" (surface3d-kind surface)
                                 "u" u "v" v)
          (nearest-grid-normal surface u v))
      (vec3-normalize candidate)))

;; `surface3d-frame-at` is the protocol-level query; the older tangent and
;; normal helpers remain useful focused accessors for regular surfaces.
(define (surface-frame-from-surface surface u v)
  (surface-frame3d (surface3d-position-at surface u v)
                   (surface3d-tangent-u-at surface u v)
                   (surface3d-tangent-v-at surface u v)
                   (surface3d-normal-at surface u v)))

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
  ;; The protocol's local mesh is deliberately style/geometry only.  The
  ;; standalone conversion is the one operation that restores the authored
  ;; transform and opacity envelope.
  (spatial-with-opacity
   (spatial-with-transform (surface-mesh3d-mesh (surface3d-local-mesh surface))
                           (spatial-transform surface))
   (spatial-opacity surface)))

; surface3d-mesh : surface3d? -> surface-mesh3d?
;; Returns renderer geometry together with topology and sample provenance.
(define (surface3d-mesh surface)
  (unless (surface3d? surface)
    (raise-argument-error 'surface3d-mesh "surface3d?" surface))
  (surface3d-local-mesh surface))

; surface3d-with-colors : surface3d? (or/c #f vector?) -> surface3d?
;;   Replaces optional immutable per-vertex semantic colour data.
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
                                       #:wireframe-color [wireframe-color theme-surface-edge]
                                       #:wireframe-width [wireframe-width 1]
                                       #:evaluator [evaluator #f]
                                       #:u-range [u-range #f]
                                       #:v-range [v-range #f]
                                       #:domain [domain #f]
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
  (unless (or (not domain) (surface-domain3d? domain))
    (raise-argument-error 'surface3d-from-generated-mesh
                          "(or/c #f surface-domain3d?)" domain))
  (define resolved-domain
    (or domain
        (and u-range v-range
             (surface-domain3d
              u-range v-range #f
              (vector 'generated-domain kind u-range v-range)))))
  (define styled
    (surface-mesh-with-style surface-mesh id material
                             (mesh3d-colors (surface-mesh3d-mesh surface-mesh))
                             wireframe-color wireframe-width))
  (generated-surface3d-value
   id transform opacity kind styled evaluator u-range v-range resolved-domain material
   wireframe-color wireframe-width diagnostics provenance
   (mesh3d-local-bounds (surface-mesh3d-mesh styled))))

;; Produces the protocol's canonical local lowering: identity placement and
;; full opacity, with surface style and immutable source provenance retained.
(define (surface3d-value->local-mesh surface)
  (define grid (surface3d-grid surface))
  (surface-mesh3d
   (mesh3d #:id (spatial-id surface)
           #:vertices (surface3d-points surface)
           #:triangles (surface-grid-triangles grid)
           #:normals (surface3d-normals surface)
           #:colors (surface3d-colors surface)
           #:material (surface3d-material surface)
           #:wireframe-color (surface3d-value-wireframe-color surface)
           #:wireframe-width (surface3d-value-wireframe-width surface))
   (for*/vector ([u-index (in-range (vector-length (surface-grid-u-values grid)))]
                 [v-index (in-range (vector-length (surface-grid-v-values grid)))])
     (hasheq 'kind 'regular-grid
             'u (vector-ref (surface-grid-u-values grid) u-index)
             'v (vector-ref (surface-grid-v-values grid) v-index)
             'u-index u-index 'v-index v-index))
   (for/vector ([triangle (in-vector (surface-grid-triangles grid))]
                [index (in-naturals)])
     (hasheq 'triangle index 'kind 'regular-grid))
   (vector 'regular-grid (surface-grid-u-values grid) (surface-grid-v-values grid)
           (surface-grid-triangles grid))
   (surface3d-diagnostics surface)))

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
            (unless (color-spec? color)
              (raise-argument-error who "color-spec?" color))
            ;; Literal transparent vertex colours remain unsupported by the
            ;; current opaque mesh path.  A token or expression is retained
            ;; here and checked after explicit-theme preparation instead.
            (define normalized (normalize-color-spec color who))
            (when (and (rgba-color? normalized)
                       (not (= (rgba-color-alpha normalized) 1)))
              (raise-argument-error who "opaque literal color-spec?" color))
            normalized))]))

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
  ;; Generated adaptive/trimmed surfaces retain their evaluator and parameter
  ;; ranges but intentionally do not pretend to have a rectangular grid.  A
  ;; fixed local probe count gives their anchors a deterministic differential
  ;; frame without reintroducing a grid-shaped public topology.
  (define resolution (surface3d-resolution surface))
  (define count (if resolution
                    (if (eq? axis 'u) (first resolution) (second resolution))
                    65))
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
       (eq? (material3d-lighting source) (material3d-lighting destination))
       (= (material3d-ambient source) (material3d-ambient destination))
       (= (material3d-diffuse source) (material3d-diffuse destination))
       (= (material3d-specular source) (material3d-specular destination))
       (equal? (material3d-specular-color source) (material3d-specular-color destination))
       (= (material3d-roughness source) (material3d-roughness destination))
       (equal? (material3d-emission source) (material3d-emission destination))
       (= (material3d-emission-strength source) (material3d-emission-strength destination))
       (eq? (material3d-double-sided? source) (material3d-double-sided? destination))
       (eq? (material3d-casts-shadow? source) (material3d-casts-shadow? destination))
       (eq? (material3d-receives-shadow? source) (material3d-receives-shadow? destination))
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
  (material3d #:color (color-mix (material3d-color source)
                                  (material3d-color destination) progress)
              #:shading (material3d-shading source)
              #:lighting (material3d-lighting source)
              #:ambient (material3d-ambient source)
              #:diffuse (material3d-diffuse source)
              #:specular (material3d-specular source)
              #:specular-color (material3d-specular-color source)
              #:roughness (material3d-roughness source)
              #:emission (material3d-emission source)
              #:emission-strength (material3d-emission-strength source)
              #:double-sided? (material3d-double-sided? source)
              #:casts-shadow? (material3d-casts-shadow? source)
              #:receives-shadow? (material3d-receives-shadow? source)
              #:wireframe? (material3d-wireframe? source)))

(define (interpolate-colors source destination progress)
  (define source-colors (surface3d-colors source))
  (define destination-colors (surface3d-colors destination))
  (cond [(and (not source-colors) (not destination-colors)) #f]
        [(and source-colors destination-colors)
         (vector->immutable-vector
          (for/vector ([source-color (in-vector source-colors)]
                       [destination-color (in-vector destination-colors)])
            (color-mix source-color destination-color progress)))]
        [else
         (raise-arguments-error 'surface3d-interpolate
                                "both surfaces either with or without per-vertex colors"
                                "source-colors" source-colors
                                "destination-colors" destination-colors)]))
