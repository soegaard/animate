#lang racket/base

;;;
;;; Spatial Maps and Homotopies
;;;

;; Defines the request vocabulary for semantic 3D maps plus the immutable mesh
;; mapper used by nonlinear maps and homotopies. Linear and affine operations
;; retain an exact affine wrapper; nonlinear operations intentionally operate on
;; the already authored vertex set and never invent adaptive topology.

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "axes3d.rkt"
         "linear3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "marker3d.rkt"
         "solids3d.rkt"
         "spatial-group.rkt"
         "spatial-path.rkt"
         "spatial-visual.rkt"
         "stroke3d.rkt"
         "transform3.rkt"
         "vec3.rkt"
         "vector-diagram3d.rkt")

(provide apply-linear3
         apply-linear3-request?
         apply-affine3
         apply-affine3-request?
         apply-pointwise3
         apply-pointwise3-request?
         apply-homotopy3
         apply-homotopy3-request?
         spatial-map-animation-request?
         (struct-out apply-linear3-request)
         (struct-out apply-affine3-request)
         (struct-out apply-pointwise3-request)
         (struct-out apply-homotopy3-request)
         (struct-out spatial-affine-map-animation)
         (struct-out spatial-pointwise-map-animation)
         (struct-out spatial-homotopy-map-animation)
         spatial-map-compiled-animation?
         pointwise-map-mesh3d
         linear-transformation-diagram3d)


;;; Requests

(struct apply-linear3-request (target-path map) #:transparent)
;; A world-coordinate linear map. The origin remains fixed.

(struct apply-affine3-request (target-path map) #:transparent)
;; A world-coordinate linear-plus-translation map.

(struct apply-pointwise3-request (target-path map-point on-failure recompute-normals?)
  #:transparent)
;; A nonlinear world-coordinate map evaluated at every retained mesh vertex.

(struct apply-homotopy3-request (target-path homotopy on-failure recompute-normals?)
  #:transparent)
;; A nonlinear world-coordinate map H(point, phase), sampled directly at phase.


;;; Public Constructors

(define (apply-linear3 target-path map)
  (check-target-path 'apply-linear3 target-path)
  (unless (linear3? map)
    (raise-argument-error 'apply-linear3 "linear3?" map))
  (apply-linear3-request target-path map))

(define (apply-affine3 target-path map)
  (check-target-path 'apply-affine3 target-path)
  (unless (affine3? map)
    (raise-argument-error 'apply-affine3 "affine3?" map))
  (apply-affine3-request target-path map))

(define (apply-pointwise3 target-path map-point
                          #:on-failure [on-failure 'error]
                          #:recompute-normals? [recompute-normals? #t])
  (check-target-path 'apply-pointwise3 target-path)
  (check-map-procedure 'apply-pointwise3 map-point 1)
  (check-failure-mode 'apply-pointwise3 on-failure)
  (unless (boolean? recompute-normals?)
    (raise-argument-error 'apply-pointwise3 "boolean?" recompute-normals?))
  (apply-pointwise3-request target-path map-point on-failure recompute-normals?))

(define (apply-homotopy3 target-path homotopy
                         #:on-failure [on-failure 'error]
                         #:recompute-normals? [recompute-normals? #t])
  (check-target-path 'apply-homotopy3 target-path)
  (check-map-procedure 'apply-homotopy3 homotopy 2)
  (check-failure-mode 'apply-homotopy3 on-failure)
  (unless (boolean? recompute-normals?)
    (raise-argument-error 'apply-homotopy3 "boolean?" recompute-normals?))
  (apply-homotopy3-request target-path homotopy on-failure recompute-normals?))


;;; Compiled Values

(struct spatial-affine-map-animation (target-path content from-map map opacity)
  #:transparent)
;; `map` is the requested world map rebased into the target's parent space.

(struct spatial-pointwise-map-animation
  (target-path source source-world-transform parent-inverse map-point on-failure recompute-normals?)
  #:transparent)

(struct spatial-homotopy-map-animation
  (target-path source source-world-transform parent-inverse homotopy on-failure recompute-normals?)
  #:transparent)

(define (spatial-map-animation-request? value)
  (or (apply-linear3-request? value)
      (apply-affine3-request? value)
      (apply-pointwise3-request? value)
      (apply-homotopy3-request? value)))

(define (spatial-map-compiled-animation? value)
  (or (spatial-affine-map-animation? value)
      (spatial-pointwise-map-animation? value)
      (spatial-homotopy-map-animation? value)))


;;; Nonlinear Mesh Mapping

; pointwise-map-mesh3d : mesh3d? affine3? affine3? (vec3? -> vec3?)
;                        #:on-failure (or/c 'error 'drop-triangle)
;                        #:recompute-normals? boolean? -> mesh3d?
;; Maps source vertices in world coordinates, then expresses retained results
;; in the target's parent coordinates. A dropped invalid vertex removes every
;; incident triangle deterministically; no holes are capped or repaired.
(define (pointwise-map-mesh3d mesh source-world-transform parent-inverse map-point
                              #:on-failure [on-failure 'error]
                              #:recompute-normals? [recompute-normals? #t])
  (unless (mesh3d? mesh)
    (raise-argument-error 'pointwise-map-mesh3d "mesh3d?" mesh))
  (unless (affine3? source-world-transform)
    (raise-argument-error 'pointwise-map-mesh3d "affine3?" source-world-transform))
  (unless (affine3? parent-inverse)
    (raise-argument-error 'pointwise-map-mesh3d "affine3?" parent-inverse))
  (check-map-procedure 'pointwise-map-mesh3d map-point 1)
  (check-failure-mode 'pointwise-map-mesh3d on-failure)
  (unless (boolean? recompute-normals?)
    (raise-argument-error 'pointwise-map-mesh3d "boolean?" recompute-normals?))
  (define source-vertices (mesh3d-vertices mesh))
  (define mapped
    (for/vector ([vertex (in-vector source-vertices)] [index (in-naturals)])
      (map-one-vertex map-point
                      (affine3-apply-point source-world-transform vertex)
                      on-failure index)))
  (define source->destination (make-vector (vector-length source-vertices) #f))
  (define destination-vertices '())
  (define destination-source-indices '())
  (define destination-triangles '())
  (define (destination-index source-index)
    (or (vector-ref source->destination source-index)
        (let ([index (length destination-vertices)])
          (vector-set! source->destination source-index index)
          (set! destination-vertices
                (append destination-vertices
                        (list (affine3-apply-point parent-inverse
                                                    (vector-ref mapped source-index)))))
          (set! destination-source-indices
                (append destination-source-indices (list source-index)))
          index)))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define indices (vector->list triangle))
    (when (andmap (lambda (index) (vec3? (vector-ref mapped index))) indices)
      (set! destination-triangles
            (append destination-triangles
                    (list (list->vector (map destination-index indices)))))))
  (define source-colors (mesh3d-colors mesh))
  (define source-normals (mesh3d-normals mesh))
  (define result
    (mesh3d
     #:id (spatial-id mesh)
     #:vertices (list->vector destination-vertices)
     #:triangles (list->vector destination-triangles)
     #:normals (and (not recompute-normals?) source-normals
                    (list->vector
                     (for/list ([source-index (in-list destination-source-indices)])
                       (vector-ref source-normals source-index))))
     #:colors (and source-colors
                   (list->vector
                    (for/list ([source-index (in-list destination-source-indices)])
                      (vector-ref source-colors source-index))))
     #:material (mesh3d-material mesh)
     #:transform identity-transform3
     #:opacity (spatial-opacity mesh)
     #:wireframe-color (mesh3d-wireframe-color mesh)
     #:wireframe-width (mesh3d-wireframe-width mesh)))
  (if recompute-normals?
      (mesh3d-smooth-normals result)
      result))

(define (map-one-vertex map-point world-point on-failure index)
  (define (failed message . details)
    (if (eq? on-failure 'drop-triangle)
        #f
        (apply raise-arguments-error 'pointwise-map-mesh3d message
               "vertex-index" index "world-point" world-point details)))
  (with-handlers ([exn:fail?
                   (lambda (exception)
                     (if (eq? on-failure 'drop-triangle)
                         #f
                         (raise-arguments-error
                          'pointwise-map-mesh3d
                          "a point map returning finite vec3 values"
                          "vertex-index" index
                          "world-point" world-point
                          "map-error" (exn-message exception))))])
    (define mapped (map-point world-point))
    (if (vec3? mapped)
        mapped
        (failed "a point map returning finite vec3 values" "map-result" mapped))))


;;; Canonical Diagram

; linear-transformation-diagram3d : #:id symbol? ... -> group3d?
;; A transformable 3D analogue of the 2D linear-map diagram. Applying one
;; `apply-linear3` request to this group changes the unit cube, coordinate
;; planes, basis arrows, and the arbitrary vector coherently.
(define (linear-transformation-diagram3d
         #:id id
         #:vector [vector (vec3 3/2 1 1/2)]
         #:cube-side [cube-side 1]
         #:plane-size [plane-size 3]
         #:transform [transform identity-transform3]
         #:opacity [opacity 1])
  (unless (symbol? id)
    (raise-argument-error 'linear-transformation-diagram3d "symbol?" id))
  (unless (vec3? vector)
    (raise-argument-error 'linear-transformation-diagram3d "vec3?" vector))
  (for ([value (in-list (list cube-side plane-size))])
    (unless (and (finite-real? value) (positive? value))
      (raise-argument-error 'linear-transformation-diagram3d
                            "positive finite cube-side and plane-size" value)))
  (unless (transform3? transform)
    (raise-argument-error 'linear-transformation-diagram3d "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'linear-transformation-diagram3d
                          "finite real in the closed unit interval" opacity))
  (define half (/ plane-size 2))
  (define cube-offset (vec3 (/ cube-side 2) (/ cube-side 2) (/ cube-side 2)))
  (group3d
   (list
    (coordinate-plane3d 'xy #:id 'xy-plane #:u-range (list (- half) half)
                        #:v-range (list (- half) half) #:color "#7fa8ff40")
    (coordinate-plane3d 'xz #:id 'xz-plane #:u-range (list (- half) half)
                        #:v-range (list (- half) half) #:color "#ff9e7f40")
    (coordinate-plane3d 'yz #:id 'yz-plane #:u-range (list (- half) half)
                        #:v-range (list (- half) half) #:color "#88d49840")
    (box3d cube-side cube-side cube-side #:id 'unit-cube #:color "#f7d35b80"
           #:transform (make-transform3 #:translation cube-offset))
    (basis-vectors3d #:id 'basis #:length 1)
    (vector-arrow3d vector #:id 'vector
                    #:shaft-style (stroke3d #:color "darkmagenta" #:width 2)
                    #:tip-style (arrow-style3d #:color "darkmagenta")))
   #:id id #:transform transform #:opacity opacity))


;;; Validation

(define (check-target-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error who
                          "nonempty spatial path rooted at a view3d, such as '(world cube)"
                          value)))

(define (check-map-procedure who value arity)
  (unless (and (procedure? value) (procedure-arity-includes? value arity))
    (raise-argument-error who
                          (format "(procedure-arity-includes/c ~a)" arity)
                          value)))

(define (check-failure-mode who value)
  (unless (memq value '(error drop-triangle))
    (raise-argument-error who "one of 'error or 'drop-triangle" value)))
