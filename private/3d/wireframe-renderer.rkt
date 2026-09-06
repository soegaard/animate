#lang racket/base

;;;
;;; Wireframe Preparation
;;;

;; Transforms indexed spatial meshes into ordered projected line segments.  It
;; remains Pict-free: the adapter consumes these values to draw ordinary paths.
;; No hidden-line removal, filled triangles, or depth buffer exists in B.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../geometry.rkt"
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "camera3d.rkt"
         "curve3d.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide (struct-out wireframe-segment)
         spatial-tree->wireframe-segments)


;;;
;;; Prepared Segment
;;;

(struct wireframe-segment (start end color width opacity)
  #:transparent
  #:guard
  (lambda (start end color width opacity who)
    (unless (and (vec2? start) (vec2? end))
      (raise-argument-error who "two vec2? endpoints" (list start end)))
    (unless (and (finite-real? width) (positive? width))
      (raise-argument-error who "positive finite line width" width))
    (unless (and (finite-real? opacity) (<= 0 opacity 1))
      (raise-argument-error who "finite opacity in the closed unit interval" opacity))
    (values start end color width opacity)))

;; wireframe-segment represents one clipped projected segment.
;;  - start    vec2?              normalized viewport start point.
;;  - end      vec2?              normalized viewport end point.
;;  - color    color-spec?        semantic wireframe colour.
;;  - width    positive-real?     cosmetic Pict line width in pixels.
;;  - opacity  spatial-opacity?   product of enclosing spatial opacities.


;;;
;;; Stable Spatial Flattening
;;;

; spatial-tree->wireframe-segments : spatial-container? camera3d? positive-real?
;                                     -> (listof wireframe-segment?)
;;   Flattens a tree in declared order, clips edges by camera depth, and projects
;; them into normalized coordinates for a viewport with the given aspect ratio.
(define (spatial-tree->wireframe-segments root camera aspect)
  (unless (spatial-container? root)
    (raise-argument-error 'spatial-tree->wireframe-segments "spatial-container?" root))
  (unless (camera3d? camera)
    (raise-argument-error 'spatial-tree->wireframe-segments "camera3d?" camera))
  (unless (and (finite-real? aspect) (positive? aspect))
    (raise-argument-error
     'spatial-tree->wireframe-segments "positive finite viewport aspect" aspect))
  (flatten-container root identity-affine3 1 camera aspect))

(define (flatten-container container parent-map parent-opacity camera aspect)
  (append*
   (for/list ([entry (in-list (spatial-child-entries container))])
     (flatten-object (spatial-child-visual entry)
                     parent-map parent-opacity camera aspect))))

(define (flatten-object object parent-map parent-opacity camera aspect)
  (define object-opacity (* parent-opacity (spatial-opacity object)))
  (cond [(affine-map3d? object)
         ;; See render-command3d: this map is semantic data, not an extra
         ;; decomposed transform to apply after its proxy transform.
         (flatten-object (affine-map3d-content object)
                         (affine3-compose parent-map (affine-map3d-map object))
                         object-opacity camera aspect)]
        [else
         (define object-map
           (affine3-compose parent-map
                            (transform3->affine3 (spatial-transform object))))
         (cond [(mesh3d? object)
         (mesh->segments object object-map object-opacity camera aspect)]
        [(curve3d? object)
         (mesh->segments (curve3d->mesh3d object)
                         object-map object-opacity camera aspect)]
        [(surface3d? object)
         (mesh->segments (surface3d->mesh3d object)
                         object-map object-opacity camera aspect)]
        [(spatial-container? object)
         (flatten-container object object-map object-opacity camera aspect)]
        [else
         ;; Future spatial leaves can exist before this first wireframe backend
         ;; learns how to draw them.  They are intentionally skipped, rather
         ;; than guessed as 2D paths or surfaces.
         '()])]))


;;;
;;; Projection and Depth Clipping
;;;

(define (mesh->segments mesh world-map opacity camera aspect)
  (for/list ([edge (in-vector (mesh3d-edges mesh))]
             #:do [(define start-index (vector-ref edge 0))
                   (define end-index (vector-ref edge 1))
                   (define start-world
                     (affine3-apply-point world-map
                                          (vector-ref (mesh3d-vertices mesh)
                                                      start-index)))
                   (define end-world
                     (affine3-apply-point world-map
                                          (vector-ref (mesh3d-vertices mesh)
                                                      end-index)))
                   (define clipped
                     (clip-view-segment
                      (camera3d-world->view camera start-world)
                      (camera3d-world->view camera end-world)
                      (camera3d-near camera)
                      (camera3d-far camera)))]
             #:when clipped)
    (define start (car clipped))
    (define end (cdr clipped))
    (wireframe-segment
     (camera3d-project-view camera start #:aspect aspect)
     (camera3d-project-view camera end #:aspect aspect)
     (mesh3d-wireframe-color mesh)
     (mesh3d-wireframe-width mesh)
     opacity)))

; clip-view-segment : vec3? vec3? positive-real? positive-real?
;                     -> (or/c #f (cons/c vec3? vec3?))
;;   Clips a camera-local segment against inclusive forward-depth near/far planes.
(define (clip-view-segment start end near far)
  (define start-depth (- (vec3-z start)))
  (define end-depth (- (vec3-z end)))
  (define-values (near-low near-high)
    (clip-depth-range start-depth end-depth near #t))
  (define-values (far-low far-high)
    (clip-depth-range start-depth end-depth far #f))
  (define low (max near-low far-low))
  (define high (min near-high far-high))
  (and (<= low high)
       (cons (vec3-lerp start end low)
             (vec3-lerp start end high))))

; clip-depth-range : finite-real? finite-real? finite-real? boolean?
;                    -> (values finite-real? finite-real?)
;;   Returns the t interval in [0,1] satisfying depth >= limit (or <= limit).
(define (clip-depth-range start-depth end-depth limit lower-bound?)
  (define delta (- end-depth start-depth))
  (cond [(zero? delta)
         (if (if lower-bound?
                 (>= start-depth limit)
                 (<= start-depth limit))
             (values 0 1)
             (values 1 0))]
        [else
         (define crossing (/ (- limit start-depth) delta))
         (cond [(and lower-bound? (positive? delta))
                (values (max 0 crossing) 1)]
               [(and lower-bound? (negative? delta))
                (values 0 (min 1 crossing))]
               [(and (not lower-bound?) (positive? delta))
                (values 0 (min 1 crossing))]
               [else
                (values (max 0 crossing) 1)])]))
