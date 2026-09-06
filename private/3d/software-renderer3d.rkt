#lang racket/base

;;; Depth-aware Software 3D Renderer

(require racket/class
         racket/list
         racket/draw
         "../color-style.rkt"
         "../preview-cancellation.rkt"
         "../visual-model.rkt"
         "affine3.rkt"
         "camera3d.rkt"
         "clipping3d.rkt"
         "compiled-view3d.rkt"
         "edge-style3d.rkt"
         "feature-edges3d.rkt"
         "frustum-clip3d.rkt"
         "light3d.rkt"
         "linear3.rkt"
         "material3d.rkt"
         "marker3d.rkt"
         "marker-raster3d.rkt"
         "mesh3d.rkt"
         "raster-target3d.rkt"
         "raster-triangle3d.rkt"
         "render-command3d.rkt"
         "software-render-diagnostics.rkt"
         "stroke-raster3d.rkt"
         "stroke3d.rkt"
         "view3d-visual.rkt"
         "vec3.rkt")

(provide render-view3d-opaque
         prepare-view3d-opaque
         prepare-compiled-view3d-opaque
         prepare-edge-overlay-strokes
         render-prepared-view3d-opaque
         current-software-render-cancellation-token
         software-render-result?
         software-render-result-target
         software-render-result-diagnostics
         software-render-preparation?
         software-render-preparation-compiled-view
         software-render-preparation-frame-spec
         software-render-preparation-diagnostics
         software-render-result->bitmap)

(struct software-render-result (target diagnostics) #:transparent)

;; A preparation holds only backend-side, camera-space triangle data.  It does
;; not mutate a `view3d`, mesh, material, or any other semantic value, so a
;; retained backend may cache it safely and rasterize it repeatedly with a
;; fresh target.  Keeping the mutable colour/depth target out of this value is
;; also what makes preparation reuse safe for random-access rendering.
(struct software-render-preparation
  (compiled-view frame-spec opaque depth-only transparent hidden-strokes visible-strokes
                 overlay-strokes hidden-points visible-points overlay-points
                 hidden-arrows visible-arrows overlay-arrows lights diagnostics)
  #:transparent)

;; The normal Pict protocol deliberately stays renderer-neutral.  Preview's
;; in-process producer parameterizes this boundary with its cooperative token,
;; allowing long meshes to stop at command, triangle, scanline, and
;; bitmap-conversion boundaries without extending every 2D renderer method.
(define current-software-render-cancellation-token
  (make-parameter
   #f
   (lambda (value)
     (unless (or (not value) (cancellation-token? value))
       (raise-argument-error 'current-software-render-cancellation-token
                             "(or/c #f cancellation-token?)" value))
     value)))

; render-view3d-opaque : view3d? exact-positive-integer? exact-positive-integer?
;                        [#:cancellation-token (or/c #f cancellation-token?)]
;                        -> software-render-result?
;; Produces one deterministic target.  Opaque triangles write depth first;
;; translucent triangles subsequently depth-test only against that opaque
;; buffer and are alpha composited far-to-near.
(define (render-view3d-opaque view width height
                               #:cancellation-token
                               [cancellation-token (current-software-render-cancellation-token)])
  (render-prepared-view3d-opaque
   (prepare-view3d-opaque view width height
                           #:cancellation-token cancellation-token)
   #:cancellation-token cancellation-token))

; prepare-view3d-opaque : view3d? exact-positive-integer? exact-positive-integer?
;                         [#:cancellation-token (or/c #f cancellation-token?)]
;                         -> software-render-preparation?
;; Flattens, clips, projects, and shades-independent prepares a view into
;; camera-space triangles.  It is the reusable geometry half of the reference
;; software renderer; raster targets are deliberately allocated by
;; `render-prepared-view3d-opaque` instead.
(define (prepare-view3d-opaque view width height
                               #:cancellation-token
                               [cancellation-token (current-software-render-cancellation-token)])
  (unless (and (procedure? view3d?) (view3d? view))
    (raise-argument-error 'prepare-view3d-opaque "view3d?" view))
  (unless (exact-positive-integer? width)
    (raise-argument-error 'prepare-view3d-opaque "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'prepare-view3d-opaque "exact-positive-integer?" height))
  (prepare-compiled-view3d-opaque
   (compile-view3d view)
   (view3d->frame3d-spec view width height)
   #:cancellation-token cancellation-token))

; prepare-compiled-view3d-opaque : compiled-view3d? frame3d-spec?
;                                  [#:cancellation-token (or/c #f cancellation-token?)]
;                                  -> software-render-preparation?
;; Prepares a camera-independent compiled scene for one camera and viewport.
(define (prepare-compiled-view3d-opaque compiled frame-spec
                                         #:cancellation-token
                                         [cancellation-token
                                          (current-software-render-cancellation-token)])
  (unless (compiled-view3d? compiled)
    (raise-argument-error 'prepare-compiled-view3d-opaque "compiled-view3d?" compiled))
  (unless (frame3d-spec? frame-spec)
    (raise-argument-error 'prepare-compiled-view3d-opaque "frame3d-spec?" frame-spec))
  (when cancellation-token (check-cancellation cancellation-token))
  (define commands (compiled-view3d->draw-mesh3d-commands compiled))
  (define camera (frame3d-spec-camera frame-spec))
  (define aspect (/ (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)))
  (define lights
    (if (null? (frame3d-spec-lights frame-spec))
        default-lights3d
        (frame3d-spec-lights frame-spec)))
  (unless (andmap light3d? lights)
    (raise-arguments-error 'prepare-compiled-view3d-opaque "a list of light3d? values"
                           "lights" lights))
  (define-values (prepared source-count clipped-count)
    (prepare-commands commands camera aspect cancellation-token))
  (define depth-only
    (filter (lambda (triangle) (eq? (prepared-triangle3d-surface-mode triangle) 'depth-only))
            prepared))
  (define visible-surface-triangles
    (filter (lambda (triangle) (eq? (prepared-triangle3d-surface-mode triangle) 'visible))
            prepared))
  (define opaque (filter prepared-triangle3d-opaque? visible-surface-triangles))
  (define transparent (filter (lambda (triangle) (not (prepared-triangle3d-opaque? triangle)))
                              visible-surface-triangles))
  (define prepared-strokes
    (append*
     (for/list ([stroke (in-vector (compiled-view3d-strokes compiled))])
       (prepare-stroke3d-segments
        (compiled-stroke3d-path stroke)
        (compiled-stroke3d-world-transform stroke)
        (compiled-stroke3d-points stroke)
        (compiled-stroke3d-closed? stroke)
        (compiled-stroke3d-style stroke)
        (compiled-stroke3d-opacity stroke)
        (compiled-stroke3d-clip-planes stroke)
        camera aspect (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
        (compiled-stroke3d-drawing-index stroke)
        #:source-kind (compiled-stroke3d-source-kind stroke)
        #:source-metadata (compiled-stroke3d-source-metadata stroke)))))
  (define edge-strokes
    (prepare-edge-overlay-strokes compiled camera aspect
                                  (frame3d-spec-width frame-spec)
                                  (frame3d-spec-height frame-spec)))
  (define all-prepared-strokes (append prepared-strokes edge-strokes))
  (define-values (edge-source-count silhouette-edge-count crease-edge-count boundary-edge-count)
    (edge-overlay-counts compiled camera))
  (define curve-source-count
    (for/sum ([stroke (in-vector (compiled-view3d-strokes compiled))])
      (+ (sub1 (vector-length (compiled-stroke3d-points stroke)))
         (if (compiled-stroke3d-closed? stroke) 1 0))))
  (define hidden-strokes
    (filter (lambda (stroke) (eq? (stroke3d-depth-mode
                                   (prepared-stroke-segment3d-style stroke))
                                  'hidden))
            all-prepared-strokes))
  (define visible-strokes
    (filter (lambda (stroke) (eq? (stroke3d-depth-mode
                                   (prepared-stroke-segment3d-style stroke))
                                  'test))
            all-prepared-strokes))
  (define overlay-strokes
    (filter (lambda (stroke) (eq? (stroke3d-depth-mode
                                   (prepared-stroke-segment3d-style stroke))
                                  'always))
            all-prepared-strokes))
  (define prepared-points
    (filter values
            (for/list ([marker (in-vector (compiled-view3d-point-markers compiled))])
              (prepare-point-marker3d
               (compiled-point-marker3d-path marker)
               (compiled-point-marker3d-position marker)
               (compiled-point-marker3d-world-transform marker)
               (compiled-point-marker3d-style marker)
               (compiled-point-marker3d-opacity marker)
               (compiled-point-marker3d-clip-planes marker)
               camera aspect (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
               (compiled-point-marker3d-drawing-index marker)))))
  (define prepared-arrows
    (filter values
            (for/list ([marker (in-vector (compiled-view3d-arrow-markers compiled))])
              (prepare-arrow-marker3d
               (compiled-arrow-marker3d-path marker)
               (compiled-arrow-marker3d-from marker)
               (compiled-arrow-marker3d-to marker)
               (compiled-arrow-marker3d-world-transform marker)
               (compiled-arrow-marker3d-style marker)
               (compiled-arrow-marker3d-opacity marker)
               (compiled-arrow-marker3d-clip-planes marker)
               camera aspect (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
               (compiled-arrow-marker3d-drawing-index marker)))))
  (define (markers-in mode access markers)
    (filter (lambda (marker) (eq? (access marker) mode)) markers))
  (define hidden-points
    (markers-in 'hidden (lambda (marker) (point-style3d-depth-mode
                                          (prepared-point-marker3d-style marker))) prepared-points))
  (define visible-points
    (markers-in 'test (lambda (marker) (point-style3d-depth-mode
                                        (prepared-point-marker3d-style marker))) prepared-points))
  (define overlay-points
    (markers-in 'always (lambda (marker) (point-style3d-depth-mode
                                          (prepared-point-marker3d-style marker))) prepared-points))
  (define hidden-arrows
    (markers-in 'hidden (lambda (marker) (arrow-style3d-depth-mode
                                          (prepared-arrow-marker3d-style marker))) prepared-arrows))
  (define visible-arrows
    (markers-in 'test (lambda (marker) (arrow-style3d-depth-mode
                                        (prepared-arrow-marker3d-style marker))) prepared-arrows))
  (define overlay-arrows
    (markers-in 'always (lambda (marker) (arrow-style3d-depth-mode
                                          (prepared-arrow-marker3d-style marker))) prepared-arrows))
  (software-render-preparation
   compiled frame-spec opaque depth-only transparent hidden-strokes visible-strokes
   overlay-strokes hidden-points visible-points overlay-points
   hidden-arrows visible-arrows overlay-arrows lights
   (software-render-diagnostics
    (length commands) source-count clipped-count 0 0
    (+ (vector-length (compiled-view3d-strokes compiled))
       (vector-length (compiled-view3d-edge-overlays compiled)))
    (+ curve-source-count edge-source-count)
    (length all-prepared-strokes)
    (* 2 (length all-prepared-strokes))
    0 0 0 silhouette-edge-count crease-edge-count boundary-edge-count)))

; render-prepared-view3d-opaque : software-render-preparation?
;                                  [#:cancellation-token (or/c #f cancellation-token?)]
;                                  -> software-render-result?
;; Rasterizes one immutable preparation into a new colour/depth target.  A
;; cancellation token is accepted here as well as at preparation time: a
;; cached preparation must never inherit a cancellation token from the frame
;; which originally populated the cache.
(define (render-prepared-view3d-opaque preparation
                                        #:cancellation-token
                                        [cancellation-token
                                         (current-software-render-cancellation-token)])
  (unless (software-render-preparation? preparation)
    (raise-argument-error 'render-prepared-view3d-opaque
                          "software-render-preparation?" preparation))
  (when cancellation-token (check-cancellation cancellation-token))
  (define frame-spec (software-render-preparation-frame-spec preparation))
  (define compiled (software-render-preparation-compiled-view preparation))
  (define target
    (make-raster-target3d (frame3d-spec-width frame-spec)
                          (frame3d-spec-height frame-spec)
                          (compiled-view3d-background compiled)))
  (define-values (opaque-raster opaque-pixels)
    (rasterize-prepared! target
                         (software-render-preparation-opaque preparation)
                         (software-render-preparation-lights preparation)
                         #:write-depth? #t #:blend? #f
                         #:cancellation-token cancellation-token))
  (define-values (depth-only-raster _depth-only-pixels)
    (rasterize-prepared! target
                         (software-render-preparation-depth-only preparation)
                         (software-render-preparation-lights preparation)
                         #:write-depth? #t #:write-color? #f #:blend? #f
                         #:cancellation-token cancellation-token))
  (define hidden-stroke-pixels
    (rasterize-prepared-strokes!
     target (software-render-preparation-hidden-strokes preparation) 'hidden))
  (define hidden-point-pixels
    (rasterize-prepared-point-markers!
     target (software-render-preparation-hidden-points preparation) 'hidden))
  (define hidden-arrow-pixels
    (rasterize-prepared-arrow-markers!
     target (software-render-preparation-hidden-arrows preparation) 'hidden))
  (define visible-stroke-pixels
    (rasterize-prepared-strokes!
     target (software-render-preparation-visible-strokes preparation) 'test))
  (define visible-point-pixels
    (rasterize-prepared-point-markers!
     target (software-render-preparation-visible-points preparation) 'test))
  (define visible-arrow-pixels
    (rasterize-prepared-arrow-markers!
     target (software-render-preparation-visible-arrows preparation) 'test))
  (define ordered-transparent
    (order-transparent-triangles
     (software-render-preparation-transparent preparation)
     (compiled-view3d-transparency-mode compiled)))
  (define-values (transparent-raster transparent-pixels)
    (rasterize-prepared! target ordered-transparent
                         (software-render-preparation-lights preparation)
                         #:write-depth? #f #:blend? #t
                         #:cancellation-token cancellation-token))
  (define overlay-stroke-pixels
    (rasterize-prepared-strokes!
     target (software-render-preparation-overlay-strokes preparation) 'always))
  (define overlay-point-pixels
    (rasterize-prepared-point-markers!
     target (software-render-preparation-overlay-points preparation) 'always))
  (define overlay-arrow-pixels
    (rasterize-prepared-arrow-markers!
     target (software-render-preparation-overlay-arrows preparation) 'always))
  (define initial-diagnostics (software-render-preparation-diagnostics preparation))
  (software-render-result
   target
   (software-render-diagnostics
    (software-render-diagnostics-command-count initial-diagnostics)
    (software-render-diagnostics-source-triangle-count initial-diagnostics)
    (software-render-diagnostics-clipped-triangle-count initial-diagnostics)
                                (+ opaque-raster depth-only-raster transparent-raster)
                                (+ opaque-pixels transparent-pixels
                                   hidden-stroke-pixels visible-stroke-pixels
                                   overlay-stroke-pixels
                                   hidden-point-pixels visible-point-pixels overlay-point-pixels
                                   hidden-arrow-pixels visible-arrow-pixels overlay-arrow-pixels)
    (software-render-diagnostics-stroke-command-count initial-diagnostics)
    (software-render-diagnostics-source-stroke-segment-count initial-diagnostics)
    (software-render-diagnostics-dash-segment-count initial-diagnostics)
    (software-render-diagnostics-stroke-triangle-count initial-diagnostics)
    (+ visible-stroke-pixels visible-point-pixels visible-arrow-pixels)
    (+ hidden-stroke-pixels hidden-point-pixels hidden-arrow-pixels)
    (+ overlay-stroke-pixels overlay-point-pixels overlay-arrow-pixels)
    (software-render-diagnostics-silhouette-edge-count initial-diagnostics)
    (software-render-diagnostics-crease-edge-count initial-diagnostics)
    (software-render-diagnostics-boundary-edge-count initial-diagnostics))))

(struct prepared-triangle3d
  (raster material opaque? depth command-index order owner surface-mode)
  #:transparent)

(define (prepare-commands commands camera aspect cancellation-token)
  (define prepared '())
  (define source-count 0)
  (define clipped-count 0)
  (define next-order 0)
  (define next-owner 0)
  (for ([command (in-list commands)])
    (when cancellation-token (check-cancellation cancellation-token))
    (define-values (triangles source clipped)
      (prepare-command command camera aspect cancellation-token next-order next-owner))
    (set! prepared (append prepared triangles))
    (set! source-count (+ source-count source))
    (set! clipped-count (+ clipped-count clipped))
    (set! next-order (+ next-order (length triangles)))
    (set! next-owner (+ next-owner (length triangles))))
  (values prepared source-count clipped-count))

;; Edge selection is deliberately per-frame: silhouettes depend on the camera
;; and crease angles depend on the current inverse-transpose normal transform.
;; The compiled resource supplies stable topology; this function only expands
;; the selected centreline edges into ordinary prepared stroke segments.
(define (prepare-edge-overlay-strokes compiled camera aspect width height)
  (define geometry-by-key
    (for/hash ([geometry (in-vector (compiled-view3d-geometries compiled))])
      (values (compiled-geometry3d-key geometry) geometry)))
  (for/fold ([all-segments '()])
            ([overlay (in-vector (compiled-view3d-edge-overlays compiled))])
    (define geometry
      (hash-ref geometry-by-key (compiled-edge-overlay3d-geometry-key overlay) #f))
    (unless geometry
      (raise-arguments-error 'prepare-compiled-view3d-opaque
                             "an edge overlay referring to compiled geometry"
                             "geometry-key" (compiled-edge-overlay3d-geometry-key overlay)))
    (define style (compiled-edge-overlay3d-style overlay))
    (define overlay-segments
      (for/fold ([edge-segments '()])
                ([edge (in-list
                        (select-feature-edges3d
                         (compiled-geometry3d-mesh geometry)
                         (compiled-edge-overlay3d-world-transform overlay)
                         (compiled-edge-overlay3d-normal-transform overlay)
                         camera style))])
        (define endpoints
          (vector (prepared-feature-edge3d-from edge)
                  (prepared-feature-edge3d-to edge)))
        (append
         edge-segments
         (if (edge-style3d-visible style)
             (prepare-stroke3d-segments
              (compiled-edge-overlay3d-path overlay) identity-affine3 endpoints #f
              (edge-style3d-visible style) (compiled-edge-overlay3d-opacity overlay)
              (compiled-edge-overlay3d-clip-planes overlay)
              camera aspect width height (compiled-edge-overlay3d-drawing-index overlay)
              #:source-kind 'mesh-edge
              #:source-metadata
              (hasheq 'edge-index (prepared-feature-edge3d-edge-index edge)
                       'edge-kind (prepared-feature-edge3d-kind edge)))
             '())
         (if (edge-style3d-hidden style)
             (prepare-stroke3d-segments
              (compiled-edge-overlay3d-path overlay) identity-affine3 endpoints #f
              (edge-style3d-hidden style) (compiled-edge-overlay3d-opacity overlay)
              (compiled-edge-overlay3d-clip-planes overlay)
              camera aspect width height (compiled-edge-overlay3d-drawing-index overlay)
              #:source-kind 'mesh-edge
              #:source-metadata
              (hasheq 'edge-index (prepared-feature-edge3d-edge-index edge)
                       'edge-kind (prepared-feature-edge3d-kind edge)))
             '()))))
    (append all-segments overlay-segments)))

(define (edge-overlay-counts compiled camera)
  (define geometry-by-key
    (for/hash ([geometry (in-vector (compiled-view3d-geometries compiled))])
      (values (compiled-geometry3d-key geometry) geometry)))
  (for/fold ([total 0] [silhouettes 0] [creases 0] [boundaries 0])
            ([overlay (in-vector (compiled-view3d-edge-overlays compiled))])
    (define geometry (hash-ref geometry-by-key (compiled-edge-overlay3d-geometry-key overlay) #f))
    (define selected
      (if geometry
          (select-feature-edges3d (compiled-geometry3d-mesh geometry)
                                  (compiled-edge-overlay3d-world-transform overlay)
                                  (compiled-edge-overlay3d-normal-transform overlay)
                                  camera (compiled-edge-overlay3d-style overlay))
          '()))
    (values (+ total (length selected))
            (+ silhouettes (count (lambda (edge) (eq? (prepared-feature-edge3d-kind edge) 'silhouette)) selected))
            (+ creases (count (lambda (edge) (eq? (prepared-feature-edge3d-kind edge) 'crease)) selected))
            (+ boundaries (count (lambda (edge) (eq? (prepared-feature-edge3d-kind edge) 'boundary)) selected)))))

(define (prepare-command command camera aspect cancellation-token first-order first-owner)
  (define mesh (draw-mesh3d-command-mesh command))
  (define material (draw-mesh3d-command-material command))
  (unless (material3d? material)
    (raise-arguments-error 'render-view3d-opaque "a mesh with material3d?"
                           "mesh-path" (draw-mesh3d-command-path command)
                           "material" material))
  (define prepared '())
  (define source-count 0)
  (define clipped-count 0)
  (for ([triangle (in-vector (mesh3d-triangles mesh))]
        [triangle-index (in-naturals)])
    (when cancellation-token (check-cancellation cancellation-token))
    (set! source-count (add1 source-count))
    (define local-points
      (for/list ([index (in-vector triangle)])
        (vector-ref (mesh3d-vertices mesh) index)))
    (define local-normal
      (vec3-cross (vec3- (second local-points) (first local-points))
                  (vec3- (third local-points) (first local-points))))
    (unless (zero? (vec3-length local-normal))
       (define normal
         (vec3-normalize
          (linear3-apply-vector (draw-mesh3d-command-normal-transform command)
                                local-normal)))
       (define mesh-normals (mesh3d-normals mesh))
       (define mesh-colors (mesh3d-colors mesh))
       (define source (list (draw-mesh3d-command-path command) triangle-index))
       (define world-polygon
         (for/list ([point (in-list local-points)] [index (in-vector triangle)])
           (define vertex-normal
             (if (and mesh-normals (eq? (material3d-shading material) 'smooth))
                 (vec3-normalize
                  (linear3-apply-vector (draw-mesh3d-command-normal-transform command)
                                        (vector-ref mesh-normals index)))
                 normal))
           (define authored-color
             (if mesh-colors (vector-ref mesh-colors index) (material3d-color material)))
           (clip-vertex3d
            (affine3-apply-point (draw-mesh3d-command-world-transform command) point)
            vertex-normal
            (rgba-with-opacity authored-color (draw-mesh3d-command-opacity command))
            source)))
       (define clipped-world
         (for/fold ([polygon world-polygon])
                   ([clip (in-list (draw-mesh3d-command-clip-planes command))])
           (clip-world-polygon polygon clip)))
       (when (>= (length clipped-world) 3)
         (for ([index (in-range 1 (sub1 (length clipped-world)))])
           (define world-triangle
             (list (first clipped-world)
                   (list-ref clipped-world index)
                   (list-ref clipped-world (add1 index))))
           (define frustum-clipped
             (apply clip-triangle3d camera aspect
                    (for/list ([vertex (in-list world-triangle)])
                      (clip-vertex3d
                       (camera3d-world->view camera (clip-vertex3d-view-position vertex))
                       (clip-vertex3d-normal vertex)
                       (clip-vertex3d-color vertex)
                       (clip-vertex3d-source vertex)))))
           (set! clipped-count (+ clipped-count (length frustum-clipped)))
           (for ([clipped-triangle (in-list frustum-clipped)])
             (define raster-triangle
               (for/vector ([vertex (in-vector clipped-triangle)])
                 (define view-position (clip-vertex3d-view-position vertex))
                 (raster-vertex3d
                  (camera3d-project-view camera view-position #:aspect aspect)
                  (- (vec3-z view-position))
                  (vec3-normalize (clip-vertex3d-normal vertex))
                  (clip-vertex3d-color vertex)
                  (clip-vertex3d-source vertex))))
             (define order (+ first-order (length prepared)))
             (define owner (+ first-owner (length prepared)))
             (set! prepared
                   (append prepared
                           (list
                            (prepared-triangle3d
                             raster-triangle material
                             (triangle-opaque? raster-triangle)
                             (/ (for/sum ([vertex (in-vector raster-triangle)])
                                  (raster-vertex3d-depth vertex))
                                3)
                             (draw-mesh3d-command-drawing-index command)
                             order owner
                             (draw-mesh3d-command-surface-mode command))))))))))
  (values prepared source-count clipped-count))

(define (triangle-opaque? triangle)
  (for/and ([vertex (in-vector triangle)])
    (= (rgba-color-alpha (raster-vertex3d-color vertex)) 1)))

(define (clip-world-polygon polygon clip)
  (cond [(null? polygon) '()]
        [else
         (define plane (clip-plane3d-plane clip))
         (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
         (define reversed '())
         (define previous (last polygon))
         (define previous-distance
           (* sign (plane-signed-distance plane (clip-vertex3d-view-position previous))))
         (for ([current (in-list polygon)])
           (define current-distance
             (* sign (plane-signed-distance plane (clip-vertex3d-view-position current))))
           (define previous-inside? (>= previous-distance -1e-8))
           (define current-inside? (>= current-distance -1e-8))
           (cond [(and previous-inside? current-inside?)
                  (set! reversed (cons current reversed))]
                 [(and previous-inside? (not current-inside?))
                  (set! reversed (cons (interpolate-clip-vertex previous current
                                                               previous-distance current-distance)
                                       reversed))]
                 [(and (not previous-inside?) current-inside?)
                  (set! reversed (cons current
                                       (cons (interpolate-clip-vertex previous current
                                                                       previous-distance current-distance)
                                             reversed)))])
           (set! previous current)
           (set! previous-distance current-distance))
         (reverse reversed)]))

(define (interpolate-clip-vertex first-vertex second-vertex first-distance second-distance)
  ;; Floating-point plane distances can be just outside the closed interval at
  ;; a vertex already considered inside.  Clamp the interpolation parameter so
  ;; all semantic attributes retain their stated [0,1] interpolation contract.
  (define progress (max 0 (min 1 (/ first-distance (- first-distance second-distance)))))
  (clip-vertex3d
   (vec3-lerp (clip-vertex3d-view-position first-vertex)
              (clip-vertex3d-view-position second-vertex) progress)
   (vec3-lerp (clip-vertex3d-normal first-vertex)
              (clip-vertex3d-normal second-vertex) progress)
   (rgba-color-lerp (clip-vertex3d-color first-vertex)
                     (clip-vertex3d-color second-vertex) progress)
   (clip-vertex3d-source first-vertex)))

(define (rgba-with-opacity color opacity)
  (define resolved (color-spec->rgba-color color 'render-view3d-opaque))
  (rgba-color (rgba-color-red resolved) (rgba-color-green resolved)
              (rgba-color-blue resolved) (* opacity (rgba-color-alpha resolved))))

(define (order-transparent-triangles triangles mode)
  (define (farther? first-triangle second-triangle)
    (cond [(> (prepared-triangle3d-depth first-triangle)
              (prepared-triangle3d-depth second-triangle)) #t]
          [(< (prepared-triangle3d-depth first-triangle)
              (prepared-triangle3d-depth second-triangle)) #f]
          [else (< (prepared-triangle3d-order first-triangle)
                   (prepared-triangle3d-order second-triangle))]))
  (case mode
    [(triangle-sorted) (sort triangles farther?)]
    [(object-sorted)
     (define grouped (make-hash))
     (for ([triangle (in-list triangles)])
       (hash-set! grouped (prepared-triangle3d-command-index triangle)
                  (append (hash-ref grouped (prepared-triangle3d-command-index triangle) '())
                          (list triangle))))
     (define objects
       (sort (hash-values grouped)
             (lambda (first-object second-object)
               (farther? (car first-object) (car second-object)))))
     (for/fold ([output '()]) ([object (in-list objects)])
       (append output
               (sort object
                     (lambda (first-triangle second-triangle)
                       (< (prepared-triangle3d-order first-triangle)
                          (prepared-triangle3d-order second-triangle))))))]))

(define (rasterize-prepared! target triangles lights #:write-depth? write-depth?
                             #:write-color? [write-color? #t] #:blend? blend?
                             #:cancellation-token cancellation-token)
  (for/fold ([raster-count 0] [pixel-count 0]) ([triangle (in-list triangles)])
    (when cancellation-token (check-cancellation cancellation-token))
    (values (add1 raster-count)
            (+ pixel-count
               (raster-triangle3d! target (prepared-triangle3d-raster triangle)
                                    (prepared-triangle3d-material triangle) lights
                                    (prepared-triangle3d-owner triangle)
                                    #:write-depth? write-depth? #:write-color? write-color? #:blend? blend?
                                    #:cancellation-token cancellation-token)))))

; software-render-result->bitmap : software-render-result?
;                                   [#:cancellation-token (or/c #f cancellation-token?)]
;                                   -> bitmap%
(define (software-render-result->bitmap result
                                        #:cancellation-token
                                        [cancellation-token (current-software-render-cancellation-token)])
  (unless (software-render-result? result)
    (raise-argument-error 'software-render-result->bitmap "software-render-result?" result))
  (when cancellation-token (check-cancellation cancellation-token))
  (define target (software-render-result-target result))
  ;; bitmap%'s third constructor argument is *monochrome?*, not alpha?.
  ;; Supplying only #t silently quantizes our entire target to black and white.
  (define bitmap (make-object bitmap% (raster-target3d-width target)
                              (raster-target3d-height target) #f #t))
  (send bitmap set-argb-pixels 0 0
        (raster-target3d-width target) (raster-target3d-height target)
        (raster-target3d->argb-bytes target))
  bitmap)
