#lang racket/base

;;;
;;; Camera-Independent Compiled Spatial Views
;;;

;; A compiled view is the retained boundary between immutable authoring values
;; and a renderer.  It contains lowered meshes plus per-instance state, but no
;; camera, viewport dimensions, lights, or raster target.  Consequently an
;; orbiting camera can reuse exactly the same compiled geometry resources.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../visual-model.rkt"
         "affine3.rkt"
         "bounds3.rkt"
         "camera3d.rkt"
         "edge-adjacency3d.rkt"
         "geometry-fingerprint3d.rkt"
         "light3d.rkt"
         "linear3.rkt"
         "mesh-analysis3d.rkt"
         "mesh3d.rkt"
         "render-command3d.rkt"
         "view3d-visual.rkt"
         "vec3.rkt")

(provide (struct-out compiled-geometry3d)
         (struct-out compiled-instance3d)
         (struct-out compiled-stroke3d)
         (struct-out compiled-point-marker3d)
         (struct-out compiled-arrow-marker3d)
         (struct-out compiled-edge-overlay3d)
         (struct-out compiled-view3d)
         (struct-out frame3d-spec)
         compile-view3d
         view3d->frame3d-spec
         compiled-view3d-primitives
         compiled-view3d->draw-mesh3d-commands)


;;;
;;; Compiled Data
;;;

(struct compiled-geometry3d
  (key mesh local-bounds face-normals edge-adjacency analysis)
  #:transparent)

;; compiled-geometry3d owns all mesh-only information. `key` is a canonical
;; semantic identity, `mesh` retains the immutable source geometry, and every
;; remaining field is a deterministic pure acceleration or diagnostic value.

(struct compiled-instance3d
  (path geometry-key world-transform normal-transform material opacity clip-planes drawing-index surface-mode)
  #:transparent)

;; compiled-instance3d holds only placement and styling.  The immutable path
;; remains available for diagnostics and picking; the geometry key resolves to
;; one member of compiled-view3d-geometries.

(struct compiled-stroke3d
  (path points closed? world-transform style opacity clip-planes drawing-index
        source-kind source-metadata)
  #:transparent)

(struct compiled-point-marker3d
  (path position world-transform style opacity clip-planes drawing-index)
  #:transparent)

(struct compiled-arrow-marker3d
  (path from to world-transform style opacity clip-planes drawing-index)
  #:transparent)

;; An edge overlay refers to the same canonical geometry resource as its
;; surface instance.  Its camera-dependent feature selection is intentionally
;; delayed until frame preparation.
(struct compiled-edge-overlay3d
  (path geometry-key world-transform normal-transform style opacity clip-planes drawing-index)
  #:transparent)

(struct compiled-view3d
  (geometries instances strokes point-markers arrow-markers edge-overlays
              background render-mode transparency-mode)
  #:transparent)

;; Collections are immutable vectors in first encounter/drawing order.  This
;; avoids exposing hash-table traversal as visual or diagnostic ordering.

(struct frame3d-spec (camera lights width height) #:transparent
  #:guard
  (lambda (camera lights width height who)
    (unless (camera3d? camera)
      (raise-argument-error who "camera3d?" camera))
    (unless (and (list? lights) (andmap light3d? lights))
      (raise-argument-error who "(listof light3d?)" lights))
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer?" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer?" height))
    (values camera (for/list ([light (in-list lights)]) light) width height)))


;;;
;;; Compilation
;;;

; compile-view3d : view3d? -> compiled-view3d?
;;   Lowers a spatial tree into reusable geometry and camera-independent draws.
(define (compile-view3d view)
  (unless (view3d? view)
    (raise-argument-error 'compile-view3d "view3d?" view))
  (define commands
    (spatial-tree->draw3d-commands
     view #:root-path (list (visual-id view))))
  (define known-geometries (make-hash))
  (define ordered-geometries '())
  (define instances '())
  (define strokes '())
  (define point-markers '())
  (define arrow-markers '())
  (define edge-overlays '())
  (for ([command (in-list commands)])
    (cond
      [(draw-mesh3d-command? command)
       (define mesh (draw-mesh3d-command-mesh command))
       (define key (mesh3d-geometry-key mesh))
       (define geometry (hash-ref known-geometries key #f))
       (define resolved-geometry
         (cond [geometry
                ;; Digest collisions are extraordinarily unlikely, but a retained
                ;; renderer must not treat one as semantic equality.  Counts are
                ;; part of the key and exact field equality is the final check.
                (unless (mesh3d-semantic-geometry=?
                         mesh (compiled-geometry3d-mesh geometry))
                  (raise-arguments-error 'compile-view3d
                                         "a collision-free geometry key"
                                         "geometry-key" key))
                geometry]
               [else
                (define created (compile-geometry mesh key))
                (hash-set! known-geometries key created)
                (set! ordered-geometries (append ordered-geometries (list created)))
                created]))
       (set! instances
             (append
              instances
              (list
               (compiled-instance3d
                (immutable-symbol-path (draw-mesh3d-command-path command))
                (compiled-geometry3d-key resolved-geometry)
                (draw-mesh3d-command-world-transform command)
                (draw-mesh3d-command-normal-transform command)
                (draw-mesh3d-command-material command)
                (draw-mesh3d-command-opacity command)
                (immutable-list (draw-mesh3d-command-clip-planes command))
                (draw-mesh3d-command-drawing-index command)
                (draw-mesh3d-command-surface-mode command)))))]
      [(draw-edge-overlay3d-command? command)
       (define mesh (draw-edge-overlay3d-command-mesh command))
       (define key (mesh3d-geometry-key mesh))
       (define geometry (hash-ref known-geometries key #f))
       (define resolved-geometry
         (cond [geometry
                (unless (mesh3d-semantic-geometry=?
                         mesh (compiled-geometry3d-mesh geometry))
                  (raise-arguments-error 'compile-view3d
                                         "a collision-free geometry key"
                                         "geometry-key" key))
                geometry]
               [else
                (define created (compile-geometry mesh key))
                (hash-set! known-geometries key created)
                (set! ordered-geometries (append ordered-geometries (list created)))
                created]))
       (set! edge-overlays
             (append edge-overlays
                     (list
                      (compiled-edge-overlay3d
                       (immutable-symbol-path (draw-edge-overlay3d-command-path command))
                       (compiled-geometry3d-key resolved-geometry)
                       (draw-edge-overlay3d-command-world-transform command)
                       (draw-edge-overlay3d-command-normal-transform command)
                       (draw-edge-overlay3d-command-style command)
                       (draw-edge-overlay3d-command-opacity command)
                       (immutable-list (draw-edge-overlay3d-command-clip-planes command))
                       (draw-edge-overlay3d-command-drawing-index command)))))]
      [(draw-stroke3d-command? command)
       (set! strokes
             (append strokes
                     (list
                      (compiled-stroke3d
                       (immutable-symbol-path (draw-stroke3d-command-path command))
                       (draw-stroke3d-command-points command)
                       (draw-stroke3d-command-closed? command)
                       (draw-stroke3d-command-world-transform command)
                       (draw-stroke3d-command-style command)
                       (draw-stroke3d-command-opacity command)
                       (immutable-list (draw-stroke3d-command-clip-planes command))
                       (draw-stroke3d-command-drawing-index command)
                       (draw-stroke3d-command-source-kind command)
                       (draw-stroke3d-command-source-metadata command)))))]
      [(draw-point-marker3d-command? command)
       (set! point-markers
             (append point-markers
                     (list
                      (compiled-point-marker3d
                       (immutable-symbol-path (draw-point-marker3d-command-path command))
                       (draw-point-marker3d-command-position command)
                       (draw-point-marker3d-command-world-transform command)
                       (draw-point-marker3d-command-style command)
                       (draw-point-marker3d-command-opacity command)
                       (immutable-list (draw-point-marker3d-command-clip-planes command))
                       (draw-point-marker3d-command-drawing-index command)))))]
      [(draw-arrow-marker3d-command? command)
       (set! arrow-markers
             (append arrow-markers
                     (list
                      (compiled-arrow-marker3d
                       (immutable-symbol-path (draw-arrow-marker3d-command-path command))
                       (draw-arrow-marker3d-command-from command)
                       (draw-arrow-marker3d-command-to command)
                       (draw-arrow-marker3d-command-world-transform command)
                       (draw-arrow-marker3d-command-style command)
                       (draw-arrow-marker3d-command-opacity command)
                       (immutable-list (draw-arrow-marker3d-command-clip-planes command))
                       (draw-arrow-marker3d-command-drawing-index command)))))]
      [else
       (raise-arguments-error 'compile-view3d "a supported spatial draw command"
                              "command" command)]))
  (compiled-view3d
   (vector->immutable-vector (list->vector ordered-geometries))
   (vector->immutable-vector (list->vector instances))
   (vector->immutable-vector (list->vector strokes))
   (vector->immutable-vector (list->vector point-markers))
   (vector->immutable-vector (list->vector arrow-markers))
   (vector->immutable-vector (list->vector edge-overlays))
   (view3d-background view)
   (view3d-render-mode view)
   (view3d-transparency-mode view)))

;; Ordered primitive view for frame preparation and future render backends.
;; The components above remain separately addressable for resource caching, but
;; no renderer may infer draw ordering by walking those component vectors.
(define (compiled-view3d-primitives compiled)
  (unless (compiled-view3d? compiled)
    (raise-argument-error 'compiled-view3d-primitives "compiled-view3d?" compiled))
  (define (drawing-index primitive)
    (cond [(compiled-instance3d? primitive) (compiled-instance3d-drawing-index primitive)]
          [(compiled-stroke3d? primitive) (compiled-stroke3d-drawing-index primitive)]
          [(compiled-point-marker3d? primitive) (compiled-point-marker3d-drawing-index primitive)]
          [(compiled-arrow-marker3d? primitive) (compiled-arrow-marker3d-drawing-index primitive)]
          [(compiled-edge-overlay3d? primitive) (compiled-edge-overlay3d-drawing-index primitive)]))
  (vector->immutable-vector
   (list->vector
    (sort (append (vector->list (compiled-view3d-instances compiled))
                  (vector->list (compiled-view3d-strokes compiled))
                  (vector->list (compiled-view3d-point-markers compiled))
                  (vector->list (compiled-view3d-arrow-markers compiled))
                  (vector->list (compiled-view3d-edge-overlays compiled)))
          < #:key drawing-index))))

(define (compile-geometry mesh key)
  (define resource-mesh (geometry-only-mesh mesh))
  (compiled-geometry3d
   key
   resource-mesh
   (mesh3d-local-bounds resource-mesh)
   (mesh-face-normals resource-mesh)
   (mesh3d-edge-adjacency resource-mesh)
   (analyze-mesh3d resource-mesh)))

;; A mesh3d also carries author-facing identity, placement, opacity, and style.
;; Geometry resources retain only the five fields that participate in the
;; canonical geometry key; all remaining render state lives on the instance.
(define (geometry-only-mesh mesh)
  (mesh3d #:id 'compiled-geometry3d
          #:vertices (mesh3d-vertices mesh)
          #:triangles (mesh3d-triangles mesh)
          #:edges (mesh3d-edges mesh)
          #:normals (mesh3d-normals mesh)
          #:colors (mesh3d-colors mesh)))

(define (mesh-face-normals mesh)
  (vector->immutable-vector
   (for/vector ([triangle (in-vector (mesh3d-triangles mesh))])
     (define first (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 0)))
     (define second (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 1)))
     (define third (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 2)))
     (define normal
       (vec3-cross (vec3- second first) (vec3- third first)))
     (and (positive? (vec3-length normal)) (vec3-normalize normal)))))

; view3d->frame3d-spec : view3d? exact-positive-integer? exact-positive-integer?
;                         -> frame3d-spec?
;;   Extracts frame-varying state.  Empty authored light lists retain the
;;   renderer's established deterministic default-light behavior.
(define (view3d->frame3d-spec view width height)
  (unless (view3d? view)
    (raise-argument-error 'view3d->frame3d-spec "view3d?" view))
  (frame3d-spec (view3d-camera view) (view3d-lights view) width height))


;;;
;;; Reference-renderer Bridge
;;;

; compiled-view3d->draw-mesh3d-commands : compiled-view3d?
;                                          -> (listof draw-mesh3d-command?)
;;   Reconstructs the historic ordered command stream for the software oracle.
;;   Backends may consume descriptors directly; this bridge keeps B--M pixels
;;   unchanged while N moves cache ownership to compiled geometry.
(define (compiled-view3d->draw-mesh3d-commands compiled)
  (unless (compiled-view3d? compiled)
    (raise-argument-error 'compiled-view3d->draw-mesh3d-commands
                          "compiled-view3d?" compiled))
  (define geometry-by-key
    (for/hash ([geometry (in-vector (compiled-view3d-geometries compiled))])
      (values (compiled-geometry3d-key geometry) geometry)))
  (for/list ([instance (in-vector (compiled-view3d-instances compiled))])
    (define geometry
      (hash-ref geometry-by-key (compiled-instance3d-geometry-key instance) #f))
    (unless geometry
      (raise-arguments-error 'compiled-view3d->draw-mesh3d-commands
                             "an instance referring to compiled geometry"
                             "geometry-key" (compiled-instance3d-geometry-key instance)))
    (draw-mesh3d-command
     (compiled-instance3d-path instance)
     (compiled-instance3d-world-transform instance)
     (compiled-instance3d-normal-transform instance)
     (compiled-geometry3d-mesh geometry)
     (compiled-instance3d-material instance)
     (compiled-instance3d-opacity instance)
     (compiled-instance3d-clip-planes instance)
     (compiled-instance3d-drawing-index instance)
     (compiled-instance3d-surface-mode instance))))

(define (immutable-symbol-path path)
  (unless (and (list? path) (andmap symbol? path))
    (raise-argument-error 'compile-view3d "(listof symbol?)" path))
  (immutable-list path))

(define (immutable-list values)
  (for/list ([value (in-list values)]) value))
