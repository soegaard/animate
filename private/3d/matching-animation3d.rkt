#lang racket/base

;;;
;;; Topology-safe Spatial Matching Animation
;;;

;; This module owns the pure vocabulary and sampling rules for U-7 matching
;; clips.  It deliberately does not know about Scene: compilation resolves a
;; live spatial path and captures its source mesh, while samples below are
;; direct functions of those two immutable endpoints and timeline progress.

(require racket/list
         (only-in racket/math pi)
         "../color-style.rkt"
         "../geometry.rkt"
         "correspondence3d.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "rotation3.rkt"
         "spatial-group.rkt"
         "spatial-path.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide transform-matching-mesh3d
         transform-matching-mesh3d-request?
         mesh-match-compiled-animation?
         spatial-line-route3d
         spatial-line-route3d?
         spatial-arc-route3d
         spatial-arc-route3d?
         spatial-bezier-route3d
         spatial-bezier-route3d?
         spatial-route3d?
         spatial-route3d-sample
         mesh3d-correspondence-compatible?
         mesh3d-matching-sample
         mesh3d-cross-fade-sample
         (struct-out transform-matching-mesh3d-request)
         (struct-out mesh-match-animation3d)
         (struct-out spatial-line-route3d-value)
         (struct-out spatial-arc-route3d-value)
         (struct-out spatial-bezier-route3d-value))


;;;
;;; Requests and compiled values
;;;

;; `destination` must carry the same spatial identity as the target.  A
;; spatial path is an identity promise, not an incidental index, so changing
;; that identity during a clip would make descendants unaddressable.
(struct transform-matching-mesh3d-request
  (target-path destination correspondence topology route)
  #:transparent)

(struct mesh-match-animation3d
  (target-path source destination correspondence topology route)
  #:transparent)

; transform-matching-mesh3d : spatial-path? mesh3d?
;                             [#:correspondence (or/c #f mesh-correspondence3d?)]
;                             [#:topology 'require-equal | 'cross-fade]
;                             [#:route spatial-route3d?]
;                             -> transform-matching-mesh3d-request?
;; Creates one scene-play request.  `require-equal` is the only mode that
;; interpolates indexed geometry.  `cross-fade` is an explicit safe fallback
;; for topology changes: the scene compiler will keep the two index arrays in
;; separate temporary mesh layers rather than pretending they correspond.
(define (transform-matching-mesh3d target-path destination
                                   #:correspondence [correspondence #f]
                                   #:topology [topology 'require-equal]
                                   #:route [route (spatial-line-route3d)])
  (check-target-path 'transform-matching-mesh3d target-path)
  (unless (mesh3d? destination)
    (raise-argument-error 'transform-matching-mesh3d "mesh3d?" destination))
  (unless (or (not correspondence) (mesh-correspondence3d? correspondence))
    (raise-argument-error
     'transform-matching-mesh3d
     "#f or mesh-correspondence3d?"
     correspondence))
  (unless (memq topology '(require-equal cross-fade))
    (raise-argument-error
     'transform-matching-mesh3d
     "(or/c 'require-equal 'cross-fade)"
     topology))
  (check-route 'transform-matching-mesh3d route)
  (transform-matching-mesh3d-request
   target-path destination correspondence topology route))


;;;
;;; Routes
;;;

(struct spatial-line-route3d-value () #:transparent)
(struct spatial-arc-route3d-value (axis angle) #:transparent)
(struct spatial-bezier-route3d-value (control-1 control-2) #:transparent)

; spatial-line-route3d : -> spatial-line-route3d?
;; Gives the default straight reference-translation route.
(define (spatial-line-route3d)
  (spatial-line-route3d-value))

; spatial-arc-route3d : #:axis vec3? #:angle finite-real? -> spatial-arc-route3d?
;; Gives a circular route in the plane perpendicular to `axis`.  A compiler
;; rejects a nonperpendicular source/destination chord rather than silently
;; projecting either endpoint into a different plane.
(define (spatial-arc-route3d #:axis axis #:angle angle)
  (unless (and (vec3? axis) (positive? (vec3-length axis)))
    (raise-argument-error 'spatial-arc-route3d "nonzero vec3?" axis))
  (unless (and (finite-real? angle) (not (zero? angle)) (< (abs angle) pi))
    (raise-argument-error
     'spatial-arc-route3d
     "nonzero finite angle with magnitude less than pi"
     angle))
  (spatial-arc-route3d-value axis angle))

; spatial-bezier-route3d : vec3? vec3? -> spatial-bezier-route3d?
;; Gives an endpoint-exact cubic reference route.  Controls are translations
;; in the target parent's local coordinates, just like a spatial transform.
(define (spatial-bezier-route3d control-1 control-2)
  (unless (vec3? control-1)
    (raise-argument-error 'spatial-bezier-route3d "vec3?" control-1))
  (unless (vec3? control-2)
    (raise-argument-error 'spatial-bezier-route3d "vec3?" control-2))
  (spatial-bezier-route3d-value control-1 control-2))

(define (spatial-line-route3d? value)
  (spatial-line-route3d-value? value))
(define (spatial-arc-route3d? value)
  (spatial-arc-route3d-value? value))
(define (spatial-bezier-route3d? value)
  (spatial-bezier-route3d-value? value))
(define (spatial-route3d? value)
  (or (spatial-line-route3d? value)
      (spatial-arc-route3d? value)
      (spatial-bezier-route3d? value)))

; spatial-route3d-sample : spatial-route3d? vec3? vec3? unit-real? -> vec3?
;; Directly samples the reference translation route.  Zero and one preserve
;; their arguments by `eq?`-independent exact value return, making endpoint
;; equality reliable even for an arc's inexact interior calculation.
(define (spatial-route3d-sample route from to progress)
  (check-route 'spatial-route3d-sample route)
  (unless (vec3? from)
    (raise-argument-error 'spatial-route3d-sample "vec3?" from))
  (unless (vec3? to)
    (raise-argument-error 'spatial-route3d-sample "vec3?" to))
  (check-progress 'spatial-route3d-sample progress)
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [(spatial-line-route3d? route) (vec3-lerp from to progress)]
        [(spatial-bezier-route3d? route)
         (bezier-point from
                       (spatial-bezier-route3d-value-control-1 route)
                       (spatial-bezier-route3d-value-control-2 route)
                       to progress)]
        [else (arc-point route from to progress)]))

(define (bezier-point first control-1 control-2 last progress)
  (define q (- 1 progress))
  (vec3+
   (vec3+
    (vec3-scale (* q q q) first)
    (vec3-scale (* 3 q q progress) control-1))
   (vec3+
    (vec3-scale (* 3 q progress progress) control-2)
    (vec3-scale (* progress progress progress) last))))

(define (arc-point route from to progress)
  (define axis (vec3-normalize (spatial-arc-route3d-value-axis route)))
  (define chord (vec3- to from))
  (define chord-length (vec3-length chord))
  (cond
    [(zero? chord-length) from]
    [else
     (define axis-component (vec3-dot axis chord))
     (unless (<= (abs axis-component) (* 1e-9 chord-length))
       (raise-arguments-error
        'spatial-route3d-sample
        "an arc axis perpendicular to the source/destination translation chord"
        "axis" axis
        "from" from
        "to" to
        "axis-chord-dot-product" axis-component))
     (define side (vec3-normalize (vec3-cross axis chord)))
     (define half-angle (/ (spatial-arc-route3d-value-angle route) 2))
     (define radius-offset (/ (/ chord-length 2) (tan half-angle)))
     (define midpoint (vec3-scale 1/2 (vec3+ from to)))
     (define center (vec3+ midpoint (vec3-scale radius-offset side)))
     (vec3+
      center
      (rotation3-apply
       (axis-angle axis (* progress
                           (spatial-arc-route3d-value-angle route)))
       (vec3- from center)))]))


;;;
;;; Topology proof and pure mesh sampling
;;;

; mesh3d-correspondence-compatible? : mesh3d? mesh3d? mesh-correspondence3d?
;                                     -> boolean?
;; True only when each source vertex/triangle has one destination partner and
;; each mapped source triangle references exactly the mapped destination
;; vertices.  It is intentionally stricter than a matching *plan*: a partial
;; plan remains useful for diagnostics/cross-fades but cannot license indexed
;; interpolation.
(define (mesh3d-correspondence-compatible? source destination correspondence)
  (and (mesh3d? source)
       (mesh3d? destination)
       (mesh-correspondence3d? correspondence)
       (complete-injective-map?
        (mesh-correspondence3d-vertex-map correspondence)
        (vector-length (mesh3d-vertices source))
        (vector-length (mesh3d-vertices destination)))
       (complete-injective-map?
        (mesh-correspondence3d-face-map correspondence)
        (vector-length (mesh3d-triangles source))
        (vector-length (mesh3d-triangles destination)))
       (equal? (vector-length (mesh3d-vertices source))
               (vector-length (mesh3d-vertices destination)))
       (equal? (vector-length (mesh3d-triangles source))
               (vector-length (mesh3d-triangles destination)))
       (for/and ([source-triangle (in-vector (mesh3d-triangles source))]
                 [source-face-index (in-naturals)])
         (define destination-triangle
           (vector-ref
            (mesh3d-triangles destination)
            (vector-ref (mesh-correspondence3d-face-map correspondence)
                        source-face-index)))
         (equal?
          (sort-indices
           (for/list ([source-vertex-index (in-vector source-triangle)])
             (vector-ref (mesh-correspondence3d-vertex-map correspondence)
                         source-vertex-index)))
          (sort-indices (vector->list destination-triangle))))))

(define (complete-injective-map? mapping source-count destination-count)
  (and (vector? mapping)
       (= (vector-length mapping) source-count)
       (= source-count destination-count)
       (let ([entries (vector->list mapping)])
         (and (andmap (lambda (index)
                        (and (exact-nonnegative-integer? index)
                             (< index destination-count)))
                      entries)
              (= (length (remove-duplicates entries)) source-count)))))

(define (sort-indices values) (sort values <))

; mesh3d-matching-sample : mesh3d? mesh3d? mesh-correspondence3d?
;                          spatial-route3d? unit-real? -> mesh3d?
;; Samples a same-topology mesh transition.  The complete source and
;; destination values are returned unchanged at endpoints.  Interior samples
;; retain the source index arrays, and move each source vertex only to the
;; vertex named by the correspondence.  Consequently this function cannot be
;; applied accidentally to an unrelated topology.
(define (mesh3d-matching-sample source destination correspondence route progress)
  (unless (mesh3d? source)
    (raise-argument-error 'mesh3d-matching-sample "mesh3d?" source))
  (unless (mesh3d? destination)
    (raise-argument-error 'mesh3d-matching-sample "mesh3d?" destination))
  (unless (mesh-correspondence3d? correspondence)
    (raise-argument-error
     'mesh3d-matching-sample "mesh-correspondence3d?" correspondence))
  (check-route 'mesh3d-matching-sample route)
  (check-progress 'mesh3d-matching-sample progress)
  (unless (mesh3d-correspondence-compatible? source destination correspondence)
    (raise-arguments-error
     'mesh3d-matching-sample
     "a complete topology-compatible mesh correspondence"
     "correspondence" correspondence
     "source-vertex-count" (vector-length (mesh3d-vertices source))
     "destination-vertex-count" (vector-length (mesh3d-vertices destination))
     "source-triangle-count" (vector-length (mesh3d-triangles source))
     "destination-triangle-count" (vector-length (mesh3d-triangles destination))))
  (cond [(zero? progress) source]
        [(= progress 1) destination]
        [else
         (define vertex-map (mesh-correspondence3d-vertex-map correspondence))
         (define from-transform (spatial-transform source))
         (define to-transform (spatial-transform destination))
         (define ordinary-transform
           (transform3-lerp from-transform to-transform progress))
         (define sampled-transform
           (make-transform3
            #:translation
            (spatial-route3d-sample
             route
             (transform3-translation from-transform)
             (transform3-translation to-transform)
             progress)
            #:rotation (transform3-rotation ordinary-transform)
            #:scale (transform3-scale ordinary-transform)))
         (mesh3d
          #:id (spatial-id source)
          #:vertices
          (for/vector ([from (in-vector (mesh3d-vertices source))]
                       [source-index (in-naturals)])
            (vec3-lerp from
                       (vector-ref (mesh3d-vertices destination)
                                   (vector-ref vertex-map source-index))
                       progress))
          #:triangles (mesh3d-triangles source)
          #:edges (mesh3d-edges source)
          #:vertex-ids (mesh3d-vertex-ids source)
          #:edge-ids (mesh3d-edge-ids source)
          #:face-ids (mesh3d-face-ids source)
          #:normals (interpolate-normals source destination vertex-map progress)
          #:colors (interpolate-colors source destination vertex-map progress)
          #:material (interpolate-material
                      (mesh3d-material source) (mesh3d-material destination) progress)
          #:transform sampled-transform
          #:opacity (real-lerp (spatial-opacity source)
                                (spatial-opacity destination) progress)
          #:wireframe-color
          (rgba-color-lerp
           (color-spec->rgba-color (mesh3d-wireframe-color source)
                                   'mesh3d-matching-sample)
           (color-spec->rgba-color (mesh3d-wireframe-color destination)
                                   'mesh3d-matching-sample)
           progress)
          #:wireframe-width
          (real-lerp (mesh3d-wireframe-width source)
                     (mesh3d-wireframe-width destination) progress))]))

; mesh3d-cross-fade-sample : mesh3d? mesh3d? spatial-route3d? unit-real?
;                            -> spatial-visual?
;; Samples topology-changing input without interpolating either index array.
;; Interior samples are a stable-ID wrapper with two independently valid mesh
;; children.  The wrapper disappears at both exact endpoints, so it cannot
;; leak a temporary spatial identity into the authored scene.
(define (mesh3d-cross-fade-sample source destination route progress)
  (unless (mesh3d? source)
    (raise-argument-error 'mesh3d-cross-fade-sample "mesh3d?" source))
  (unless (mesh3d? destination)
    (raise-argument-error 'mesh3d-cross-fade-sample "mesh3d?" destination))
  (unless (eq? (spatial-id source) (spatial-id destination))
    (raise-arguments-error
     'mesh3d-cross-fade-sample
     "source and destination meshes with one stable spatial identity"
     "source-id" (spatial-id source)
     "destination-id" (spatial-id destination)))
  (check-route 'mesh3d-cross-fade-sample route)
  (check-progress 'mesh3d-cross-fade-sample progress)
  (cond [(zero? progress) source]
        [(= progress 1) destination]
        [else
         (define source-id (spatial-id source))
         (define temporary-source-id
           (string->symbol (format "__mesh-match-source-~a" source-id)))
         (define temporary-destination-id
           (string->symbol (format "__mesh-match-destination-~a" source-id)))
         (define source-transform
           (mesh-transform-with-route source source destination route progress))
         (define destination-transform
           (mesh-transform-with-route destination source destination route progress))
         (group3d
          (list (mesh-copy source temporary-source-id source-transform
                           (* (- 1 progress) (spatial-opacity source)))
                (mesh-copy destination temporary-destination-id destination-transform
                           (* progress (spatial-opacity destination))))
          #:id source-id)]))

(define (mesh-transform-with-route visual source destination route progress)
  (define transform (spatial-transform visual))
  (make-transform3
   #:translation
   (spatial-route3d-sample
    route
    (transform3-translation (spatial-transform source))
    (transform3-translation (spatial-transform destination))
    progress)
   #:rotation (transform3-rotation transform)
   #:scale (transform3-scale transform)))

(define (mesh-copy mesh id transform opacity)
  (mesh3d #:id id
          #:vertices (mesh3d-vertices mesh)
          #:triangles (mesh3d-triangles mesh)
          #:edges (mesh3d-edges mesh)
          #:vertex-ids (mesh3d-vertex-ids mesh)
          #:edge-ids (mesh3d-edge-ids mesh)
          #:face-ids (mesh3d-face-ids mesh)
          #:normals (mesh3d-normals mesh)
          #:colors (mesh3d-colors mesh)
          #:material (mesh3d-material mesh)
          #:transform transform #:opacity opacity
          #:wireframe-color (mesh3d-wireframe-color mesh)
          #:wireframe-width (mesh3d-wireframe-width mesh)))

(define (interpolate-normals source destination vertex-map progress)
  (define from (mesh3d-normals source))
  (define to (mesh3d-normals destination))
  (and from to
       (for/vector ([normal (in-vector from)] [index (in-naturals)])
         (define blended
           (vec3-lerp normal (vector-ref to (vector-ref vertex-map index)) progress))
         ;; Opposing normals can cancel exactly.  Preserve a defined vector in
         ;; that degenerate interior rather than making a renderer normalize 0.
         (if (zero? (vec3-length blended)) normal (vec3-normalize blended)))))

(define (interpolate-colors source destination vertex-map progress)
  (define from (mesh3d-colors source))
  (define to (mesh3d-colors destination))
  (and from to
       (for/vector ([color (in-vector from)] [index (in-naturals)])
         (rgba-color-lerp
          (color-spec->rgba-color color 'mesh3d-matching-sample)
          (color-spec->rgba-color (vector-ref to (vector-ref vertex-map index))
                                  'mesh3d-matching-sample)
          progress))))

(define (interpolate-material from to progress)
  (material3d
   #:color (rgba-color-lerp (material3d-color from) (material3d-color to) progress)
   ;; All currently rendered shading choices are discrete semantics.  Snapping
   ;; at the midpoint avoids synthesizing an undocumented fourth mode.
   #:shading (if (< progress 1/2) (material3d-shading from) (material3d-shading to))
   #:ambient (real-lerp (material3d-ambient from) (material3d-ambient to) progress)
   #:diffuse (real-lerp (material3d-diffuse from) (material3d-diffuse to) progress)
   #:specular (real-lerp (material3d-specular from) (material3d-specular to) progress)
   #:roughness (real-lerp (material3d-roughness from) (material3d-roughness to) progress)
   #:double-sided? (if (< progress 1/2)
                        (material3d-double-sided? from)
                        (material3d-double-sided? to))
   #:wireframe? (if (< progress 1/2)
                    (material3d-wireframe? from)
                    (material3d-wireframe? to))))

(define (mesh-match-compiled-animation? value)
  (mesh-match-animation3d? value))

(define (check-target-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error who "view-rooted nonempty spatial path" value)))

(define (check-route who value)
  (unless (spatial-route3d? value)
    (raise-argument-error who "spatial-route3d?" value)))

(define (check-progress who value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-argument-error who "finite real in [0, 1]" value)))
