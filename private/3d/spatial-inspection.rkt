#lang racket/base

;;;
;;; Immutable Spatial Inspection and Exact Picking
;;;

;; Inspection is derived from one sampled `view3d`; it never writes selection,
;; acceleration, or overlay resources into a semantic scene value.  The same
;; data can therefore support a GUI preview, headless tests, and a future
;; retained renderer.

(require racket/list
         "../geometry.rkt"
         "../visual-model.rkt"
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "bounds3.rkt"
         "bvh3d.rkt"
         "camera3d.rkt"
         "curve3d.rkt"
         "edge-style3d.rkt"
         "feature-edges3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "marker3d.rkt"
         "marker-raster3d.rkt"
         "parametric-surface3d.rkt"
         "ray-plane.rkt"
         "render-command3d.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "stroke-raster3d.rkt"
         "stroke3d.rkt"
         "transform3.rkt"
         "tube-style3d.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide (struct-out spatial-inspection)
         (struct-out spatial-pick)
         spatial-pick-kind
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

(define (spatial-pick-kind pick)
  (unless (spatial-pick? pick)
    (raise-argument-error 'spatial-pick-kind "spatial-pick?" pick))
  (hash-ref (spatial-pick-metadata pick) 'kind 'mesh-triangle))

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
        [(and (curve3d? object) (tube-style3d? (curve3d-style object)))
         (curve3d->mesh3d object)]
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
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-argument-error 'view3d-pixel-pick "positive viewport dimensions"
                          (vector width height)))
  (define ray
    (camera3d-pixel-ray (view3d-camera view) pixel-x pixel-y
                        #:width width #:height height))
  ;; Mesh picking remains exact ray/triangle intersection.  Screen-space
  ;; marks do not have a world-volume to intersect, so a pixel pick supplements
  ;; those exact hits with the same projected disc/triangle footprints used by
  ;; the renderer.  This keeps a visible point or arrowhead selectable after
  ;; Stage O stopped representing it as a miniature mesh.
  (define mesh-hit (view3d-pick view ray))
  (define stroke-hits
    (view3d-stroke-picks view pixel-x pixel-y width height ray mesh-hit))
  (define marker-hits
    (view3d-screen-marker-picks view pixel-x pixel-y width height ray mesh-hit))
  (define hits (append (if mesh-hit (list mesh-hit) '()) stroke-hits marker-hits))
  (and (pair? hits) (car (sort hits pick-before?))))

(define (view3d-stroke-picks view pixel-x pixel-y width height ray opaque-hit)
  (define camera (view3d-camera view))
  (define aspect (/ width height))
  (define inspections
    (for/hash ([inspection (in-list (view3d-spatial-inspections view))])
      (values (spatial-inspection-path inspection) inspection)))
  (define commands
    (spatial-tree->draw3d-commands view #:root-path (list (visual-id view))))
  (define regular-segments
    (append*
     (for/list ([command (in-list commands)] #:when (draw-stroke3d-command? command))
       (prepare-stroke3d-segments
        (draw-stroke3d-command-path command)
        (draw-stroke3d-command-world-transform command)
        (draw-stroke3d-command-points command)
        (draw-stroke3d-command-closed? command)
        (draw-stroke3d-command-style command)
        (draw-stroke3d-command-opacity command)
        (draw-stroke3d-command-clip-planes command)
        camera aspect width height (draw-stroke3d-command-drawing-index command)))))
  (define edge-segments
    (append*
     (for/list ([command (in-list commands)] #:when (draw-edge-overlay3d-command? command))
       (define style (draw-edge-overlay3d-command-style command))
       (append*
        (for/list ([edge (in-list
                          (select-feature-edges3d
                           (draw-edge-overlay3d-command-mesh command)
                           (draw-edge-overlay3d-command-world-transform command)
                           (draw-edge-overlay3d-command-normal-transform command)
                           camera style))])
          (define endpoints
            (vector (prepared-feature-edge3d-from edge)
                    (prepared-feature-edge3d-to edge)))
          (append
           (if (edge-style3d-visible style)
               (prepare-stroke3d-segments
                (draw-edge-overlay3d-command-path command) identity-affine3 endpoints #f
                (edge-style3d-visible style) (draw-edge-overlay3d-command-opacity command)
                (draw-edge-overlay3d-command-clip-planes command)
                camera aspect width height (draw-edge-overlay3d-command-drawing-index command)
                #:source-kind 'mesh-edge
                #:source-metadata
                (hasheq 'edge-index (prepared-feature-edge3d-edge-index edge)
                         'edge-kind (prepared-feature-edge3d-kind edge)))
               '())
           (if (edge-style3d-hidden style)
               (prepare-stroke3d-segments
                (draw-edge-overlay3d-command-path command) identity-affine3 endpoints #f
                (edge-style3d-hidden style) (draw-edge-overlay3d-command-opacity command)
                (draw-edge-overlay3d-command-clip-planes command)
                camera aspect width height (draw-edge-overlay3d-command-drawing-index command)
                #:source-kind 'mesh-edge
                #:source-metadata
                (hasheq 'edge-index (prepared-feature-edge3d-edge-index edge)
                         'edge-kind (prepared-feature-edge3d-kind edge)))
               '())))))))
  (filter values
          (for/list ([segment (in-list (append regular-segments edge-segments))])
            (stroke-segment-pixel-pick segment inspections camera pixel-x pixel-y ray opaque-hit))))

(define (stroke-segment-pixel-pick segment inspections camera pixel-x pixel-y ray opaque-hit)
  (define first-x (prepared-stroke-segment3d-start-x segment))
  (define first-y (prepared-stroke-segment3d-start-y segment))
  (define second-x (prepared-stroke-segment3d-end-x segment))
  (define second-y (prepared-stroke-segment3d-end-y segment))
  (define dx (- second-x first-x))
  (define dy (- second-y first-y))
  (define length-squared (+ (* dx dx) (* dy dy)))
  (define progress
    (if (zero? length-squared) 0
        (max 0 (min 1 (/ (+ (* (- pixel-x first-x) dx) (* (- pixel-y first-y) dy))
                            length-squared)))))
  (define closest-x (+ first-x (* progress dx)))
  (define closest-y (+ first-y (* progress dy)))
  (define pixel-distance
    (sqrt (screen-distance-squared pixel-x pixel-y closest-x closest-y)))
  (define style (prepared-stroke-segment3d-style segment))
  (define depth (stroke-depth-at-progress segment progress))
  (define opaque-depth
    (and opaque-hit (camera3d-view-depth camera (spatial-pick-point opaque-hit))))
  (define mode (stroke3d-depth-mode style))
  (define depth-visible?
    (case mode
      [(always) #t]
      [(test) (or (not opaque-depth) (<= (- depth (stroke3d-depth-bias style)) opaque-depth))]
      [(hidden) (and opaque-depth (> (+ depth (stroke3d-depth-bias style)) opaque-depth))]))
  (and depth-visible?
       (<= pixel-distance (+ (/ (prepared-stroke-segment3d-width segment) 2) 2))
       (let* ([path (prepared-stroke-segment3d-path segment)]
              [inspection (hash-ref inspections path #f)]
              [source-progress
               (+ (prepared-stroke-segment3d-source-start-progress segment)
                  (* progress
                     (- (prepared-stroke-segment3d-source-end-progress segment)
                        (prepared-stroke-segment3d-source-start-progress segment))))]
              [world-point
               (vec3-lerp (prepared-stroke-segment3d-start-world segment)
                           (prepared-stroke-segment3d-end-world segment)
                           progress)])
         (and inspection
              (spatial-pick
               inspection path #f world-point (vec3-distance (ray3-origin ray) world-point)
               #f (vec3-scale -1 (camera3d-forward camera)) ray
               (hasheq 'kind 'stroke-segment
                       'drawing-index (prepared-stroke-segment3d-drawing-index segment)
                       'segment-index (prepared-stroke-segment3d-source-segment segment)
                       'segment-progress source-progress
                       'view-depth depth
                       'pixel-distance pixel-distance
                       'source-kind (prepared-stroke-segment3d-source-kind segment)
                       'source-metadata (prepared-stroke-segment3d-source-metadata segment)
                       'style style))))))

(define (stroke-depth-at-progress segment progress)
  (define first (prepared-stroke-segment3d-start-depth segment))
  (define second (prepared-stroke-segment3d-end-depth segment))
  (/ 1.0 (+ (/ (- 1 progress) first) (/ progress second))))

(define (view3d-screen-marker-picks view pixel-x pixel-y width height ray opaque-hit)
  (define camera (view3d-camera view))
  (define aspect (/ width height))
  (define inspections
    (for/hash ([inspection (in-list (view3d-spatial-inspections view))])
      (values (spatial-inspection-path inspection) inspection)))
  (filter values
          (for/list ([command
                      (in-list
                       (spatial-tree->draw3d-commands
                        view #:root-path (list (visual-id view))))])
            (cond [(draw-point-marker3d-command? command)
                   (point-marker-pixel-pick command inspections camera aspect
                                            pixel-x pixel-y width height ray opaque-hit)]
                  [(draw-arrow-marker3d-command? command)
                   (arrow-marker-pixel-pick command inspections camera aspect
                                            pixel-x pixel-y width height ray opaque-hit)]
                  [else #f]))))

(define (point-marker-pixel-pick command inspections camera aspect pixel-x pixel-y width height ray opaque-hit)
  ;; Use the renderer's preparation rather than duplicating projection and
  ;; clipping. A marker excluded by an author clip plane must not remain
  ;; clickable merely because its un-clipped anchor happens to project here.
  (define marker
    (prepare-point-marker3d
     (draw-point-marker3d-command-path command)
     (draw-point-marker3d-command-position command)
     (draw-point-marker3d-command-world-transform command)
     (draw-point-marker3d-command-style command)
     (draw-point-marker3d-command-opacity command)
     (draw-point-marker3d-command-clip-planes command)
     camera aspect width height (draw-point-marker3d-command-drawing-index command)))
  (and marker
       (<= (screen-distance-squared pixel-x pixel-y
                                    (prepared-point-marker3d-x marker)
                                    (prepared-point-marker3d-y marker))
           (let ([radius (prepared-point-marker3d-radius marker)]) (* radius radius)))
       (marker-spatial-pick (prepared-point-marker3d-path marker)
                             (hash-ref inspections (prepared-point-marker3d-path marker) #f)
                             (prepared-point-marker3d-world-position marker) camera ray
                             (prepared-point-marker3d-drawing-index marker)
                             'point-marker (prepared-point-marker3d-style marker) opaque-hit)))

(define (arrow-marker-pixel-pick command inspections camera aspect pixel-x pixel-y width height ray opaque-hit)
  (define marker
    (prepare-arrow-marker3d
     (draw-arrow-marker3d-command-path command)
     (draw-arrow-marker3d-command-from command)
     (draw-arrow-marker3d-command-to command)
     (draw-arrow-marker3d-command-world-transform command)
     (draw-arrow-marker3d-command-style command)
     (draw-arrow-marker3d-command-opacity command)
     (draw-arrow-marker3d-command-clip-planes command)
     camera aspect width height (draw-arrow-marker3d-command-drawing-index command)))
  (and marker
       (let* ([tip (cons (prepared-arrow-marker3d-tip-x marker)
                         (prepared-arrow-marker3d-tip-y marker))]
              [base-x (prepared-arrow-marker3d-base-x marker)]
              [base-y (prepared-arrow-marker3d-base-y marker)]
              [dx (- (car tip) base-x)]
              [dy (- (cdr tip) base-y)]
              [length (sqrt (+ (* dx dx) (* dy dy)))])
         (and (positive? length)
              (let* ([normal-x (/ (- dy) length)]
                     [normal-y (/ dx length)]
                     [half-width (prepared-arrow-marker3d-half-width marker)]
                     [first-base (cons (+ base-x (* normal-x half-width))
                                       (+ base-y (* normal-y half-width)))]
                     [second-base (cons (- base-x (* normal-x half-width))
                                        (- base-y (* normal-y half-width)))])
                (and (screen-point-in-triangle? pixel-x pixel-y tip first-base second-base)
                     (marker-spatial-pick (prepared-arrow-marker3d-path marker)
                                           (hash-ref inspections
                                                     (prepared-arrow-marker3d-path marker)
                                                     #f)
                                           (prepared-arrow-marker3d-tip-world marker) camera ray
                                           (prepared-arrow-marker3d-drawing-index marker)
                                           'arrow-marker (prepared-arrow-marker3d-style marker)
                                           opaque-hit)))))))

(define (marker-spatial-pick path inspection point camera ray drawing-index kind style opaque-hit)
  (define depth (camera3d-view-depth camera point))
  (define opaque-depth
    (and opaque-hit (camera3d-view-depth camera (spatial-pick-point opaque-hit))))
  (define mode
    (if (point-style3d? style)
        (point-style3d-depth-mode style)
        (arrow-style3d-depth-mode style)))
  (define bias
    (if (point-style3d? style)
        (point-style3d-depth-bias style)
        (arrow-style3d-depth-bias style)))
  (and inspection
       (case mode
         [(always) #t]
         [(test) (or (not opaque-depth) (<= (- depth bias) opaque-depth))]
         [(hidden) (and opaque-depth (> (+ depth bias) opaque-depth))])
       (spatial-pick inspection path #f point (vec3-distance (ray3-origin ray) point)
                     #f (vec3-scale -1 (camera3d-forward camera)) ray
                     (hasheq 'kind kind
                             'drawing-index drawing-index
                             'marker-style style))))

(define (project-screen camera point aspect width height)
  (define projected (camera3d-project camera point #:aspect aspect))
  (and projected
       (cons (* width (/ (+ (vec2-x projected) 1) 2))
             (* height (/ (- 1 (vec2-y projected)) 2)))))

(define (world-diameter-pixels diameter point camera aspect width height)
  (define half (/ diameter 2))
  (define first (project-screen camera
                                (vec3- point (vec3-scale half (camera3d-right camera)))
                                aspect width height))
  (define second (project-screen camera
                                 (vec3+ point (vec3-scale half (camera3d-right camera)))
                                 aspect width height))
  (if (and first second)
      (sqrt (screen-distance-squared (car first) (cdr first) (car second) (cdr second)))
      0))

(define (screen-distance-squared first-x first-y second-x second-y)
  (define dx (- second-x first-x))
  (define dy (- second-y first-y))
  (+ (* dx dx) (* dy dy)))

(define (screen-point-in-triangle? x y first second third)
  (define (cross start end)
    (- (* (- (car end) (car start)) (- y (cdr start)))
       (* (- (cdr end) (cdr start)) (- x (car start)))))
  (define first-cross (cross first second))
  (define second-cross (cross second third))
  (define third-cross (cross third first))
  (or (and (>= first-cross 0) (>= second-cross 0) (>= third-cross 0))
      (and (<= first-cross 0) (<= second-cross 0) (<= third-cross 0))))

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
            (hasheq 'kind 'mesh-triangle
                    'material (draw-mesh3d-command-material command)
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
                  (< (or (spatial-pick-triangle-index first) -1)
                     (or (spatial-pick-triangle-index second) -1))))]))
