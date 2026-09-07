#lang racket/base

;;;
;;; Polyhedral Net Face Groups and Hinge-Rotation Animation
;;;

;; A prepared net records source-to-flat rigid frames.  This module turns that
;; pure data into independent face meshes and samples the *tree of hinges*.
;; Sampling never interpolates face vertices or affine matrix entries: a child
;; first rotates about its source hinge, then inherits its parent's current
;; rigid map.  Consequently the shared edge remains coincident at every phase.

(require racket/list
         "../geometry.rkt"
         "affine3.rkt"
         "linear3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "polyhedral-complex3d.rkt"
         "polyhedron-net3d.rkt"
         "rotation3.rkt"
         "spatial-group.rkt"
         "spatial-path.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide polyhedron-net3d-group
         polyhedron-net3d-sample-transforms
         unfold-polyhedron3d
         unfold-polyhedron3d-request?
         fold-polyhedron3d
         fold-polyhedron3d-request?
         polyhedron-fold-animation-request?
         polyhedron-fold-compiled-animation?
         (struct-out unfold-polyhedron3d-request)
         (struct-out fold-polyhedron3d-request)
         (struct-out polyhedron-fold-animation))


;;;
;;; Canonical face group
;;;

; polyhedron-net3d-group : polyhedral-complex3d? polyhedron-net3d? #:id symbol?
;                          [#:face-materials (or/c #f (vectorof material3d?))]
;                          -> group3d?
;; Builds one direct mesh child for every polygonal face.  The child IDs are
;; the stable IDs carried by the prepared net, so an explicit face `front`
;; lives at `(net front)`.  The source mesh must be untransformed: net frames
;; currently describe its local coordinates, and silently baking a general
;; scale or shear here would invalidate the prepared hinge geometry.
(define (polyhedron-net3d-group complex net #:id id
                                #:face-materials [face-materials #f])
  (unless (polyhedral-complex3d? complex)
    (raise-argument-error 'polyhedron-net3d-group "polyhedral-complex3d?" complex))
  (unless (polyhedron-net3d? net)
    (raise-argument-error 'polyhedron-net3d-group "polyhedron-net3d?" net))
  (unless (symbol? id)
    (raise-argument-error 'polyhedron-net3d-group "symbol?" id))
  (define source (polyhedral-complex3d-mesh complex))
  (unless (equal? (spatial-transform source) identity-transform3)
    (raise-arguments-error
     'polyhedron-net3d-group
     "a polyhedral complex whose source mesh has identity local transform"
     "mesh-transform" (spatial-transform source)))
  (define faces (polyhedral-complex3d-faces complex))
  (define child-ids (polyhedron-net3d-face-child-ids net))
  (unless (= (vector-length faces) (vector-length child-ids))
    (raise-arguments-error
     'polyhedron-net3d-group
     "a prepared net for the supplied polyhedral complex"
     "face-count" (vector-length faces)
     "net-face-count" (vector-length child-ids)))
  (when face-materials
    (unless (and (vector? face-materials)
                 (= (vector-length face-materials) (vector-length faces))
                 (andmap material3d? (vector->list face-materials)))
      (raise-argument-error
       'polyhedron-net3d-group
       "#f or a vector of material3d values, one for each polygonal face"
       face-materials)))
  (group3d
   (for/list ([face (in-vector faces)] [child-id (in-vector child-ids)]
              [index (in-naturals)])
     (face-mesh source face child-id
                (if face-materials
                    (vector-ref face-materials index)
                    (mesh3d-material source))))
   #:id id))

(define (face-mesh source face child-id material)
  (define source-triangles (mesh3d-triangles source))
  (define source-vertices (mesh3d-vertices source))
  (define triangle-indices (polyhedral-face3d-triangle-indices face))
  (define vertex-indices
    (sort
     (remove-duplicates
      (append*
       (for/list ([triangle-index (in-vector triangle-indices)])
         (vector->list (vector-ref source-triangles triangle-index)))))
     <))
  (define old->new
    (for/hash ([old-index (in-list vertex-indices)] [new-index (in-naturals)])
      (values old-index new-index)))
  (define (select values)
    (and values
         (vector->immutable-vector
          (list->vector
           (for/list ([index (in-list vertex-indices)])
             (vector-ref values index))))))
  (mesh3d
   #:id child-id
   #:vertices
   (vector->immutable-vector
    (list->vector
     (for/list ([index (in-list vertex-indices)])
       (vector-ref source-vertices index))))
   #:triangles
   (vector->immutable-vector
    (for/vector ([triangle-index (in-vector triangle-indices)])
      (define triangle (vector-ref source-triangles triangle-index))
      (vector-immutable
       (hash-ref old->new (vector-ref triangle 0))
       (hash-ref old->new (vector-ref triangle 1))
       (hash-ref old->new (vector-ref triangle 2)))))
   #:vertex-ids (select (mesh3d-vertex-ids source))
   #:face-ids
   (and (mesh3d-face-ids source)
        (vector->immutable-vector
         (for/vector ([index (in-vector triangle-indices)])
           (mesh3d-face-id source index))))
   #:normals (select (mesh3d-normals source))
   #:colors (select (mesh3d-colors source))
   #:material material
   #:wireframe-color (mesh3d-wireframe-color source)
   #:wireframe-width (mesh3d-wireframe-width source)))


;;;
;;; Requests and compiled value
;;;

(struct unfold-polyhedron3d-request (target-path net) #:transparent)
(struct fold-polyhedron3d-request (target-path net) #:transparent)

;; `source-transforms` and `flat-transforms` are immutable vectors in face
;; index order.  At the endpoint we install those captured values directly,
;; preserving exact authored values instead of reconstructing them from an
;; intermediate rotation.
(struct polyhedron-fold-animation
  (target-path net direction face-paths source-transforms flat-transforms)
  #:transparent)

(define (unfold-polyhedron3d target-path net)
  (check-target-path 'unfold-polyhedron3d target-path)
  (check-net 'unfold-polyhedron3d net)
  (unfold-polyhedron3d-request target-path net))

(define (fold-polyhedron3d target-path net)
  (check-target-path 'fold-polyhedron3d target-path)
  (check-net 'fold-polyhedron3d net)
  (fold-polyhedron3d-request target-path net))

(define (polyhedron-fold-animation-request? value)
  (or (unfold-polyhedron3d-request? value)
      (fold-polyhedron3d-request? value)))

(define (polyhedron-fold-compiled-animation? value)
  (polyhedron-fold-animation? value))


;;;
;;; Rigid sampling
;;;

; polyhedron-net3d-sample-transforms : polyhedron-net3d? unit-real?
;                                      -> immutable-vectorof transform3?
;; Returns local source-to-sampled transforms for the face meshes made by
;; `polyhedron-net3d-group`.  Zero and one return exact identity/flat values;
;; interior phases rotate each descendant around its source hinge and inherit
;; its parent's sampled rigid map.
(define (polyhedron-net3d-sample-transforms net progress)
  (check-net 'polyhedron-net3d-sample-transforms net)
  (check-unit-progress 'polyhedron-net3d-sample-transforms progress)
  (define count (vector-length (polyhedron-net3d-face-transforms net)))
  (define identities
    (vector->immutable-vector
     (for/vector ([unused (in-range count)]) identity-transform3)))
  (define flat (polyhedron-net3d-flat-transforms net))
  (cond [(zero? progress) identities]
        [(= progress 1) flat]
        [else
         (vector->immutable-vector
          (for/vector ([map (in-vector (polyhedron-net3d-sample-affines net progress))])
            (affine->rigid-transform map)))]))

(define (polyhedron-net3d-flat-transforms net)
  (define root (polyhedron-net3d-root-face net))
  (vector->immutable-vector
   (for/vector ([frame (in-vector (polyhedron-net3d-face-transforms net))]
                [index (in-naturals)])
     ;; The root plane defines the net's coordinate system, so it deliberately
     ;; remains in its authored source placement.  This avoids numerical drift
     ;; from reconstructing the identity frame through floating normals.
     (if (= index root)
         identity-transform3
         (affine->rigid-transform (net-frame->affine frame))))))

(define (polyhedron-net3d-sample-affines net progress)
  (define frames (polyhedron-net3d-face-transforms net))
  (define final-maps
    (vector->immutable-vector
     (for/vector ([frame (in-vector frames)] [index (in-naturals)])
       (if (= index (polyhedron-net3d-root-face net))
           identity-affine3
           (net-frame->affine frame)))))
  (define sampled (make-vector (vector-length frames) #f))
  (vector-set! sampled (polyhedron-net3d-root-face net) identity-affine3)
  (for ([hinge (in-vector (polyhedron-net3d-hinge-tree net))])
    (define parent-index (net-hinge3d-parent hinge))
    (define child-index (net-hinge3d-child hinge))
    (define parent-now (vector-ref sampled parent-index))
    (unless parent-now
      (raise-arguments-error
       'polyhedron-net3d-sample-transforms
       "a parent-before-child net hinge tree"
       "hinge" hinge))
    (define parent-final (vector-ref final-maps parent-index))
    (define child-final (vector-ref final-maps child-index))
    ;; In source coordinates this is precisely the child's turn around its
    ;; shared edge after the parent is already flat.
    (define local-final
      (affine3-compose (affine3-invert parent-final) child-final))
    (define child-frame (vector-ref frames child-index))
    (define hinge-origin (net-face-transform3d-source-origin child-frame))
    (define hinge-axis (net-face-transform3d-source-e child-frame))
    (define angle
      (hinge-angle local-final hinge-axis
                   (net-face-transform3d-source-f child-frame)))
    (define local-now
      (rotation-about-line hinge-origin hinge-axis (* progress angle)))
    (vector-set! sampled child-index
                 (affine3-compose parent-now local-now)))
  (vector->immutable-vector
   (for/vector ([map (in-vector sampled)] [index (in-naturals)])
     (or map
         (raise-arguments-error
          'polyhedron-net3d-sample-transforms
          "a hinge tree reaching every polygonal face"
          "unreached-face" index)))))

(define (net-frame->affine frame)
  ;; The source and target frames are orthonormal.  This direct basis product
  ;; retains the semantic source frame rather than trying to infer a rotation
  ;; from a potentially noisy matrix before the final conversion to transform3.
  (define source-e (net-face-transform3d-source-e frame))
  (define source-f (net-face-transform3d-source-f frame))
  (define source-n (net-face-transform3d-source-n frame))
  (define target-e (net-face-transform3d-target-e frame))
  (define target-f (net-face-transform3d-target-f frame))
  (define target-n (net-face-transform3d-target-n frame))
  (define (map-vector vector)
    (vec3+
     (vec3-scale (vec3-dot vector source-e) target-e)
     (vec3+
      (vec3-scale (vec3-dot vector source-f) target-f)
      (vec3-scale (vec3-dot vector source-n) target-n))))
  (define linear
    (columns->linear3 (map-vector x-axis3)
                      (map-vector y-axis3)
                      (map-vector z-axis3)))
  (define origin (net-face-transform3d-source-origin frame))
  (affine3 linear
           (vec3- (net-face-transform3d-target-origin frame)
                  (linear3-apply-vector linear origin))))

(define (columns->linear3 first second third)
  (linear3 (vec3-x first) (vec3-x second) (vec3-x third)
           (vec3-y first) (vec3-y second) (vec3-y third)
           (vec3-z first) (vec3-z second) (vec3-z third)))

(define (hinge-angle local-map axis reference)
  (define turned (affine3-apply-vector local-map reference))
  ;; atan(y,x) retains the signed side of a hinge.  A half turn is the one
  ;; ambiguous case, but both signs describe the same physical half rotation.
  (atan (vec3-dot axis (vec3-cross reference turned))
        (vec3-dot reference turned)))

(define (rotation-about-line origin axis angle)
  (define rotation (axis-angle axis angle))
  (define linear (rotation3->linear3 rotation))
  (affine3 linear
           (vec3- origin (linear3-apply-vector linear origin))))

(define (affine->rigid-transform map)
  (define linear (affine3-linear map))
  (make-transform3
   #:translation (affine3-translation map)
   #:rotation
   (rotation3-look-at
    (linear3-apply-vector linear z-axis3)
    #:up (linear3-apply-vector linear y-axis3))))


;;;
;;; Validation
;;;

(define (check-target-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error
     who
     "nonempty spatial path rooted at a view3d, such as '(world net)"
     value)))

(define (check-net who value)
  (unless (polyhedron-net3d? value)
    (raise-argument-error who "polyhedron-net3d?" value)))

(define (check-unit-progress who value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-argument-error who "finite real in the closed unit interval" value)))
