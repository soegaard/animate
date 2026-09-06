#lang racket/base

;;;
;;; Immutable Spatial Inspection and Exact Picking
;;;

;; Inspection is derived from one sampled `view3d`; it never writes selection,
;; acceleration, or overlay resources into a semantic scene value.  The same
;; data can therefore support a GUI preview, headless tests, and a future
;; retained renderer.

(require racket/list
         "../visual-model.rkt"
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "bounds3.rkt"
         "bvh3d.rkt"
         "camera3d.rkt"
         "curve3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "ray-plane.rkt"
         "render-command3d.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide (struct-out spatial-inspection)
         (struct-out spatial-pick)
         view3d-spatial-inspections
         view3d-spatial-inspection-tree
         view3d-spatial-inspection-at
         view3d-pick
         view3d-pixel-pick)

;; All positions are in semantic world coordinates except `view-position`,
;; which is camera-local, and `projected-position`, which is NDC. `metadata`
;; is an immutable hash for deliberately extensible inspector information.
(struct spatial-inspection
  (path kind local-transform world-transform local-bounds world-bounds material
        triangle-count vertex-count camera-position view-position
        projected-position view-depth metadata)
  #:transparent)

;; Exact nearest hit. `path` identifies the rendered mesh/curve/surface;
;; `triangle-index` is its authored or generated mesh index. Barycentric uses
;; the first/second/third triangle vertices; normal is the world-space
;; interpolated/face normal currently available from the indexed mesh.
(struct spatial-pick
  (inspection path triangle-index point distance barycentric normal ray metadata)
  #:transparent)

;; view3d-spatial-inspections : view3d? -> (listof spatial-inspection?)
;; Returns pre-order records in deterministic child order, including groups so
;; a GUI can show the full spatial hierarchy instead of only draw commands.
(define (view3d-spatial-inspections view)
  (unless (view3d? view)
    (raise-argument-error 'view3d-spatial-inspections "view3d?" view))
  (define camera (view3d-camera view))
  (define aspect (/ (view3d-width view) (view3d-height view)))
  (append-map
   (lambda (child)
     (inspect-object child identity-affine3 (list (visual-id view)) camera aspect))
   (view3d-children view)))

;; Kept as an explicit name for preview code. A flat pre-order list preserves
;; stable path/depth and is less lossy than a second mutable tree structure.
(define view3d-spatial-inspection-tree view3d-spatial-inspections)

(define (view3d-spatial-inspection-at view path)
  (unless (view3d? view)
    (raise-argument-error 'view3d-spatial-inspection-at "view3d?" view))
  (unless (and (list? path) (andmap symbol? path))
    (raise-argument-error 'view3d-spatial-inspection-at "(listof symbol?)" path))
  (for/first ([inspection (in-list (view3d-spatial-inspections view))]
              #:when (equal? (spatial-inspection-path inspection) path))
    inspection))

(define (inspect-object object parent-transform parent-path camera aspect)
  ;; affine-map3d is path-transparent. Its content receives the complete map
  ;; at the same rooted identity; the wrapper itself is not an artificial
  ;; second item in an author's inspector tree.
  (if (affine-map3d? object)
      (inspect-object (affine-map3d-content object)
                      (affine3-compose parent-transform (affine-map3d-map object))
                      parent-path camera aspect)
      (let* ([world-transform
              (affine3-compose parent-transform (spatial-visual->affine3 object))]
             [path (append parent-path (list (spatial-id object)))]
             [local-bounds (spatial-local-bounds object)]
             [world-bounds (object-world-bounds object parent-transform)]
             [mesh (object->mesh object)]
             [anchor (and (not (aabb3-empty? world-bounds))
                          (aabb3-center world-bounds))]
             [view-position (and anchor (camera3d-world->view camera anchor))]
             [projected-position
              (and anchor (camera3d-project camera anchor #:aspect aspect))]
             [view-depth (and anchor (camera3d-view-depth camera anchor))]
             [inspection
              (spatial-inspection
               path (spatial-kind object) (spatial-transform object) world-transform
               local-bounds world-bounds
               (and mesh (mesh3d-material mesh))
               (if mesh (vector-length (mesh3d-triangles mesh)) 0)
               (if mesh (vector-length (mesh3d-vertices mesh)) 0)
               (camera3d-position camera) view-position projected-position view-depth
               (hasheq 'id (spatial-id object)
                       'opacity (spatial-opacity object)
                       'container? (spatial-container? object)
                       'mesh? (and mesh #t)))])
        (cons inspection
              (if (spatial-container? object)
                  (append-map
                   (lambda (entry)
                     (inspect-object (spatial-child-visual entry)
                                     world-transform path camera aspect))
                   (spatial-child-entries object))
                  '())))))

(define (object-world-bounds object parent-transform)
  (cond [(affine-map3d? object)
         (object-world-bounds
          (affine-map3d-content object)
          (affine3-compose parent-transform (affine-map3d-map object)))]
        [else
         (define world-transform
           (affine3-compose parent-transform (spatial-visual->affine3 object)))
         (if (spatial-container? object)
             (for/fold ([bounds aabb3-empty])
                       ([entry (in-list (spatial-child-entries object))])
               (aabb3-union bounds
                            (object-world-bounds (spatial-child-visual entry)
                                                 world-transform)))
             (aabb3-transform (spatial-local-bounds object) world-transform))]))

(define (object->mesh object)
  (cond [(mesh3d? object) object]
        [(curve3d? object) (curve3d->mesh3d object)]
        [(surface3d? object) (surface3d->mesh3d object)]
        [else #f]))

(define (spatial-kind object)
  (cond [(mesh3d? object) 'mesh]
        [(curve3d? object) 'curve]
        [(surface3d? object) 'surface]
        [(spatial-container? object) 'group]
        [else 'spatial-visual]))

;; view3d-pick : view3d? ray3? -> (or/c #f spatial-pick?)
;; Applies the complete phase sequence: view/world AABB culling, local BVH
;; traversal, exact triangle intersection, and deterministic nearest tie.
(define (view3d-pick view ray)
  (unless (view3d? view)
    (raise-argument-error 'view3d-pick "view3d?" view))
  (unless (ray3? ray)
    (raise-argument-error 'view3d-pick "ray3?" ray))
  (define inspections
    (for/hash ([inspection (in-list (view3d-spatial-inspections view))])
      (values (spatial-inspection-path inspection) inspection)))
  (define hits
    (append-map
     (lambda (command)
       (command-hits command ray (hash-ref inspections (draw-mesh3d-command-path command) #f)))
     (spatial-tree->draw-mesh3d-commands
      view #:root-path (list (visual-id view)))))
  (and (pair? hits)
       (car (sort hits pick-before?))))

;; view3d-pixel-pick : view3d? pixel pixel #:width positive-int #:height positive-int
;;                       -> (or/c #f spatial-pick?)
(define (view3d-pixel-pick view pixel-x pixel-y #:width width #:height height)
  (unless (view3d? view)
    (raise-argument-error 'view3d-pixel-pick "view3d?" view))
  (view3d-pick view
               (camera3d-pixel-ray (view3d-camera view) pixel-x pixel-y
                                   #:width width #:height height)))

(define (command-hits command world-ray inspection)
  (define world-transform (draw-mesh3d-command-world-transform command))
  (define inverse
    (with-handlers ([exn:fail? (lambda (_exception) #f)])
      (affine3-invert world-transform)))
  (cond [(not inverse) '()]
        [else
         (define local-ray
           (ray3 (affine3-apply-point inverse (ray3-origin world-ray))
                 (affine3-apply-vector inverse (ray3-direction world-ray))))
         (define mesh (draw-mesh3d-command-mesh command))
         (define bvh (mesh3d-bvh mesh))
         (define normal-transform (affine3-normal-transform world-transform))
         (for/list ([triangle-index (in-list (bvh3d-ray-candidates bvh local-ray))]
                    #:do [(define triangle (vector-ref (mesh3d-triangles mesh) triangle-index))
                          (define points
                            (for/list ([index (in-vector triangle)])
                              (vector-ref (mesh3d-vertices mesh) index)))
                          (define local-hit
                            (ray3-intersect-triangle local-ray
                                                     (first points) (second points) (third points)))]
                    #:when local-hit)
           (define normal
             (vec3-normalize
              (linear3-apply-vector normal-transform
                                    (ray3-triangle-hit-normal local-hit))))
           (spatial-pick
            inspection
            (draw-mesh3d-command-path command)
            triangle-index
            ;; The affine transformed local ray preserves ray parameter t.
            ;; Recompute on the original ray to avoid coordinate-rounding drift.
            (ray3-at world-ray (ray3-triangle-hit-distance local-hit))
            (ray3-triangle-hit-distance local-hit)
            (ray3-triangle-hit-barycentric local-hit)
            normal
            world-ray
            (hasheq 'material (draw-mesh3d-command-material command)
                    'drawing-index (draw-mesh3d-command-drawing-index command)
                    'command-opacity (draw-mesh3d-command-opacity command)
                    ;; This is inspection data, not a new semantic mesh.  It
                    ;; lets a preview draw the exact selected triangle without
                    ;; reverse engineering it from a cached raster image.
                    'world-triangle
                    (for/list ([point (in-list points)])
                      (affine3-apply-point world-transform point)))))]))

(define (pick-before? first second)
  (cond [(< (spatial-pick-distance first) (spatial-pick-distance second)) #t]
        [(> (spatial-pick-distance first) (spatial-pick-distance second)) #f]
        [else
         (define first-index (hash-ref (spatial-pick-metadata first) 'drawing-index))
         (define second-index (hash-ref (spatial-pick-metadata second) 'drawing-index))
         (or (< first-index second-index)
             (and (= first-index second-index)
                  (< (spatial-pick-triangle-index first)
                     (spatial-pick-triangle-index second))))]))
