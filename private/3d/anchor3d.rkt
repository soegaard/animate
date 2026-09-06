#lang racket/base

;;;
;;; Immutable Spatial Anchor Descriptors
;;;

(require racket/generic
         racket/list
         "../geometry.rkt"
         "../visual-model.rkt"
         "affine3.rkt"
         "bounds3.rkt"
         "curve3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "spatial-visual.rkt"
         "spatial-path.rkt"
         "transform3.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide gen:anchor3d
         anchor3d?
         anchor3d-resolve
         anchor3d-normal
         anchor3d-tangent
         anchor3d-identity
         (struct-out resolved-anchor3d)
         point-anchor3d
         spatial-origin-anchor3d
         bounds-anchor3d
         vertex-anchor3d
         edge-anchor3d
         face-anchor3d
         curve-anchor3d
         surface-anchor3d)

(struct resolved-anchor3d (world-point normal tangent source-path source-kind provenance)
  #:transparent)

(define-generics anchor3d
  (anchor3d-resolve anchor3d view)
  (anchor3d-normal anchor3d view)
  (anchor3d-tangent anchor3d view)
  (anchor3d-identity anchor3d))

(struct point-anchor3d-value (point id)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (check-view 'point-anchor3d view)
     (resolved-anchor3d (point-anchor3d-value-point anchor) #f #f #f 'point
                        (point-anchor3d-value-id anchor)))
   (define (anchor3d-normal anchor view) #f)
   (define (anchor3d-tangent anchor view) #f)
   (define (anchor3d-identity anchor)
     (vector 'point (point-anchor3d-value-id anchor) (point-anchor3d-value-point anchor)))])

(struct spatial-origin-anchor3d-value (path)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path object map) (resolve-object 'spatial-origin-anchor3d view
                                                       (spatial-origin-anchor3d-value-path anchor)))
     (resolved-anchor3d (affine3-translation map) #f #f path 'spatial-origin
                        (vector 'spatial-origin path)))
   (define (anchor3d-normal anchor view) #f)
   (define (anchor3d-tangent anchor view) #f)
   (define (anchor3d-identity anchor) (vector 'spatial-origin (spatial-origin-anchor3d-value-path anchor)))])

(struct bounds-anchor3d-value (path corner)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path object map) (resolve-object 'bounds-anchor3d view (bounds-anchor3d-value-path anchor)))
     (define bounds (spatial-local-bounds object))
     (when (aabb3-empty? bounds)
       (raise-arguments-error 'bounds-anchor3d "a spatial object with nonempty bounds" "path" path))
     (resolved-anchor3d (affine3-apply-point map (corner-point bounds (bounds-anchor3d-value-corner anchor)))
                        #f #f path 'bounds (vector 'bounds (bounds-anchor3d-value-corner anchor))))
   (define (anchor3d-normal anchor view) #f)
   (define (anchor3d-tangent anchor view) #f)
   (define (anchor3d-identity anchor) (vector 'bounds (bounds-anchor3d-value-path anchor)
                                               (bounds-anchor3d-value-corner anchor)))])

(struct vertex-anchor3d-value (path index)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path mesh map) (resolve-mesh 'vertex-anchor3d view (vertex-anchor3d-value-path anchor)))
     (define index (vertex-anchor3d-value-index anchor))
     (check-index 'vertex-anchor3d index (vector-length (mesh3d-vertices mesh)))
     (define normal (and (mesh3d-normals mesh) (vector-ref (mesh3d-normals mesh) index)))
     (resolved-anchor3d (affine3-apply-point map (vector-ref (mesh3d-vertices mesh) index))
                        (and normal (world-normal map normal)) #f path 'vertex
                        (vector 'vertex index)))
   (define (anchor3d-normal anchor view) (resolved-anchor3d-normal (anchor3d-resolve anchor view)))
   (define (anchor3d-tangent anchor view) #f)
   (define (anchor3d-identity anchor) (vector 'vertex (vertex-anchor3d-value-path anchor)
                                               (vertex-anchor3d-value-index anchor)))])

(struct edge-anchor3d-value (path index at)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path mesh map) (resolve-mesh 'edge-anchor3d view (edge-anchor3d-value-path anchor)))
     (define index (edge-anchor3d-value-index anchor))
     (check-index 'edge-anchor3d index (vector-length (mesh3d-edges mesh)))
     (define edge (vector-ref (mesh3d-edges mesh) index))
     (define first (vector-ref (mesh3d-vertices mesh) (vector-ref edge 0)))
     (define second (vector-ref (mesh3d-vertices mesh) (vector-ref edge 1)))
     (define tangent (safe-normal (affine3-apply-vector map (vec3- second first))))
     (resolved-anchor3d (affine3-apply-point map (vec3-lerp first second (edge-anchor3d-value-at anchor)))
                        #f tangent path 'edge (vector 'edge index (edge-anchor3d-value-at anchor))))
   (define (anchor3d-normal anchor view) #f)
   (define (anchor3d-tangent anchor view) (resolved-anchor3d-tangent (anchor3d-resolve anchor view)))
   (define (anchor3d-identity anchor) (vector 'edge (edge-anchor3d-value-path anchor)
                                               (edge-anchor3d-value-index anchor) (edge-anchor3d-value-at anchor)))])

(struct face-anchor3d-value (path index kind)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path mesh map) (resolve-mesh 'face-anchor3d view (face-anchor3d-value-path anchor)))
     (define index (face-anchor3d-value-index anchor))
     (check-index 'face-anchor3d index (vector-length (mesh3d-triangles mesh)))
     (define triangle (vector-ref (mesh3d-triangles mesh) index))
     (define vertices (for/list ([vertex-index (in-vector triangle)])
                        (vector-ref (mesh3d-vertices mesh) vertex-index)))
     (define point (vec3-scale 1/3 (for/fold ([sum origin3]) ([vertex (in-list vertices)]) (vec3+ sum vertex))))
     (define normal (safe-normal (vec3-cross (vec3- (second vertices) (first vertices))
                                             (vec3- (third vertices) (first vertices)))))
     (resolved-anchor3d (affine3-apply-point map point) (world-normal map normal) #f path 'face
                        (vector 'face index (face-anchor3d-value-kind anchor))))
   (define (anchor3d-normal anchor view) (resolved-anchor3d-normal (anchor3d-resolve anchor view)))
   (define (anchor3d-tangent anchor view) #f)
   (define (anchor3d-identity anchor) (vector 'face (face-anchor3d-value-path anchor)
                                               (face-anchor3d-value-index anchor)
                                               (face-anchor3d-value-kind anchor)))])

(struct curve-anchor3d-value (path progress)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path object map) (resolve-object 'curve-anchor3d view (curve-anchor3d-value-path anchor)))
     (unless (curve3d? object) (raise-arguments-error 'curve-anchor3d "a curve3d at path" "path" path))
     (define progress (curve-anchor3d-value-progress anchor))
     (resolved-anchor3d (affine3-apply-point map (curve3d-point-at object progress)) #f
                        (safe-normal (affine3-apply-vector map (curve3d-tangent-at object progress)))
                        path 'curve (vector 'curve progress)))
   (define (anchor3d-normal anchor view) #f)
   (define (anchor3d-tangent anchor view) (resolved-anchor3d-tangent (anchor3d-resolve anchor view)))
   (define (anchor3d-identity anchor) (vector 'curve (curve-anchor3d-value-path anchor)
                                               (curve-anchor3d-value-progress anchor)))])

(struct surface-anchor3d-value (path u v)
  #:transparent
  #:methods gen:anchor3d
  [(define (anchor3d-resolve anchor view)
     (define-values (path object map) (resolve-object 'surface-anchor3d view (surface-anchor3d-value-path anchor)))
     (unless (surface3d? object) (raise-arguments-error 'surface-anchor3d "a surface3d at path" "path" path))
     (define point (surface3d-position-at? object (surface-anchor3d-value-u anchor)
                                           (surface-anchor3d-value-v anchor)))
     (unless point
       (raise-arguments-error 'surface-anchor3d "a point inside the retained surface domain"
                              "u" (surface-anchor3d-value-u anchor) "v" (surface-anchor3d-value-v anchor)))
     ;; Fixed-grid surfaces expose analytic-or-finite-difference tangent data.
     ;; Generated surfaces that cannot yet provide a parameter frame still
     ;; resolve their point truthfully, rather than pretending a face normal is
     ;; an evaluator normal.  Their frame provenance is added with the Q
     ;; surface-picking path until adaptive frame interpolation is introduced.
     (define u (surface-anchor3d-value-u anchor))
     (define v (surface-anchor3d-value-v anchor))
     (define local-tangent
       (with-handlers ([exn:fail? (lambda (_exception) #f)])
         (surface3d-tangent-u-at object u v)))
     (define local-normal
       (with-handlers ([exn:fail? (lambda (_exception) #f)])
         (surface3d-normal-at object u v)))
     (resolved-anchor3d (affine3-apply-point map point)
                        (world-normal map local-normal)
                        (and local-tangent
                             (safe-normal (affine3-apply-vector map local-tangent)))
                        path 'surface
                        (vector 'surface (surface-anchor3d-value-u anchor) (surface-anchor3d-value-v anchor))))
   (define (anchor3d-normal anchor view) (resolved-anchor3d-normal (anchor3d-resolve anchor view)))
   (define (anchor3d-tangent anchor view) (resolved-anchor3d-tangent (anchor3d-resolve anchor view)))
   (define (anchor3d-identity anchor) (vector 'surface (surface-anchor3d-value-path anchor)
                                               (surface-anchor3d-value-u anchor) (surface-anchor3d-value-v anchor)))])

(define (point-anchor3d point #:id [id 'point])
  (unless (vec3? point) (raise-argument-error 'point-anchor3d "vec3?" point))
  (unless (symbol? id) (raise-argument-error 'point-anchor3d "symbol?" id))
  (point-anchor3d-value point id))
(define (spatial-origin-anchor3d path) (check-path 'spatial-origin-anchor3d path) (spatial-origin-anchor3d-value path))
(define (bounds-anchor3d path corner)
  (check-path 'bounds-anchor3d path)
  (unless (memq corner '(center top-right-front top-left-front top-right-back top-left-back
                         bottom-right-front bottom-left-front bottom-right-back bottom-left-back))
    (raise-argument-error 'bounds-anchor3d "named bounds corner" corner))
  (bounds-anchor3d-value path corner))
(define (vertex-anchor3d path index) (check-path 'vertex-anchor3d path) (check-natural 'vertex-anchor3d index) (vertex-anchor3d-value path index))
(define (edge-anchor3d path index #:at [at 1/2])
  (check-path 'edge-anchor3d path) (check-natural 'edge-anchor3d index) (check-unit 'edge-anchor3d at)
  (edge-anchor3d-value path index at))
(define (face-anchor3d path index #:kind [kind 'centroid])
  (check-path 'face-anchor3d path) (check-natural 'face-anchor3d index)
  (unless (eq? kind 'centroid) (raise-argument-error 'face-anchor3d "centroid face kind" kind))
  (face-anchor3d-value path index kind))
(define (curve-anchor3d path #:progress [progress 1/2])
  (check-path 'curve-anchor3d path) (check-unit 'curve-anchor3d progress)
  (curve-anchor3d-value path progress))
(define (surface-anchor3d path #:u u #:v v)
  (check-path 'surface-anchor3d path)
  (unless (and (finite-real? u) (finite-real? v))
    (raise-argument-error 'surface-anchor3d "finite u and v parameters" (vector u v)))
  (surface-anchor3d-value path u v))

(define (check-view who view) (unless (view3d? view) (raise-argument-error who "view3d?" view)))
(define (check-path who path) (unless (spatial-path? path) (raise-argument-error who "spatial path" path)))
(define (check-natural who value) (unless (exact-nonnegative-integer? value) (raise-argument-error who "exact nonnegative integer?" value)))
(define (check-unit who value) (unless (and (finite-real? value) (<= 0 value 1)) (raise-argument-error who "finite real in [0, 1]" value)))
(define (resolve-object who view path)
  (check-view who view)
  (define rooted (if (eq? (car path) (visual-id view)) path (cons (visual-id view) path)))
  (values rooted (view3d-spatial-ref view rooted) (view3d-spatial-world-transform view rooted)))
(define (resolve-mesh who view path)
  (define-values (rooted object map) (resolve-object who view path))
  (define mesh (cond [(mesh3d? object) object] [(surface3d? object) (surface3d->mesh3d object)] [else #f]))
  (unless mesh (raise-arguments-error who "a mesh3d or surface3d at path" "path" rooted))
  (values rooted mesh map))
(define (check-index who index count)
  (unless (< index count) (raise-arguments-error who "in-range mesh index" "index" index "count" count)))
(define (safe-normal vector)
  (and (positive? (vec3-length vector)) (vec3-normalize vector)))
(define (world-normal map normal)
  (and normal (with-handlers ([exn:fail? (lambda (_exception) #f)])
                (safe-normal (linear3-apply-vector (affine3-normal-transform map) normal)))))
(define (corner-point bounds corner)
  (define low (aabb3-minimum bounds)) (define high (aabb3-maximum bounds))
  (define (x right?) (if right? (vec3-x high) (vec3-x low)))
  (define (y top?) (if top? (vec3-y high) (vec3-y low)))
  (define (z front?) (if front? (vec3-z high) (vec3-z low)))
  (case corner
    [(center) (aabb3-center bounds)]
    [(top-right-front) (vec3 (x #t) (y #t) (z #t))]
    [(top-left-front) (vec3 (x #f) (y #t) (z #t))]
    [(top-right-back) (vec3 (x #t) (y #t) (z #f))]
    [(top-left-back) (vec3 (x #f) (y #t) (z #f))]
    [(bottom-right-front) (vec3 (x #t) (y #f) (z #t))]
    [(bottom-left-front) (vec3 (x #f) (y #f) (z #t))]
    [(bottom-right-back) (vec3 (x #t) (y #f) (z #f))]
    [else (vec3 (x #f) (y #f) (z #f))]))
