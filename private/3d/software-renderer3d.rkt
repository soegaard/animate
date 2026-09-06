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
         "frustum-clip3d.rkt"
         "light3d.rkt"
         "linear3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "raster-target3d.rkt"
         "raster-triangle3d.rkt"
         "render-command3d.rkt"
         "software-render-diagnostics.rkt"
         "view3d-visual.rkt"
         "vec3.rkt")

(provide render-view3d-opaque
         prepare-view3d-opaque
         render-prepared-view3d-opaque
         current-software-render-cancellation-token
         software-render-result?
         software-render-result-target
         software-render-result-diagnostics
         software-render-preparation?
         software-render-preparation-view
         software-render-preparation-width
         software-render-preparation-height
         software-render-preparation-diagnostics
         software-render-result->bitmap)

(struct software-render-result (target diagnostics) #:transparent)

;; A preparation holds only backend-side, camera-space triangle data.  It does
;; not mutate a `view3d`, mesh, material, or any other semantic value, so a
;; retained backend may cache it safely and rasterize it repeatedly with a
;; fresh target.  Keeping the mutable colour/depth target out of this value is
;; also what makes preparation reuse safe for random-access rendering.
(struct software-render-preparation
  (view width height opaque transparent lights diagnostics)
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
  (when cancellation-token (check-cancellation cancellation-token))
  (define commands
    (spatial-tree->draw-mesh3d-commands
     view #:root-path (list (visual-id view))))
  (define camera (view3d-camera view))
  (define aspect (/ width height))
  (define lights (if (null? (view3d-lights view)) default-lights3d (view3d-lights view)))
  (unless (andmap light3d? lights)
    (raise-arguments-error 'prepare-view3d-opaque "a list of light3d? values"
                           "lights" lights))
  (define-values (prepared source-count clipped-count)
    (prepare-commands commands camera aspect cancellation-token))
  (define opaque (filter prepared-triangle3d-opaque? prepared))
  (define transparent (filter (lambda (triangle) (not (prepared-triangle3d-opaque? triangle)))
                              prepared))
  (software-render-preparation
   view width height opaque transparent lights
   (software-render-diagnostics (length commands) source-count clipped-count 0 0)))

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
  (define target
    (make-raster-target3d (software-render-preparation-width preparation)
                          (software-render-preparation-height preparation)
                          (view3d-background
                           (software-render-preparation-view preparation))))
  (define-values (opaque-raster opaque-pixels)
    (rasterize-prepared! target
                         (software-render-preparation-opaque preparation)
                         (software-render-preparation-lights preparation)
                         #:write-depth? #t #:blend? #f
                         #:cancellation-token cancellation-token))
  (define ordered-transparent
    (order-transparent-triangles
     (software-render-preparation-transparent preparation)
     (view3d-transparency-mode (software-render-preparation-view preparation))))
  (define-values (transparent-raster transparent-pixels)
    (rasterize-prepared! target ordered-transparent
                         (software-render-preparation-lights preparation)
                         #:write-depth? #f #:blend? #t
                         #:cancellation-token cancellation-token))
  (define initial-diagnostics (software-render-preparation-diagnostics preparation))
  (software-render-result
   target
   (software-render-diagnostics
    (software-render-diagnostics-command-count initial-diagnostics)
    (software-render-diagnostics-source-triangle-count initial-diagnostics)
    (software-render-diagnostics-clipped-triangle-count initial-diagnostics)
                                (+ opaque-raster transparent-raster)
                                (+ opaque-pixels transparent-pixels))))

(struct prepared-triangle3d
  (raster material opaque? depth command-index order owner)
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
                             order owner)))))))))
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

(define (rasterize-prepared! target triangles lights #:write-depth? write-depth? #:blend? blend?
                             #:cancellation-token cancellation-token)
  (for/fold ([raster-count 0] [pixel-count 0]) ([triangle (in-list triangles)])
    (when cancellation-token (check-cancellation cancellation-token))
    (values (add1 raster-count)
            (+ pixel-count
               (raster-triangle3d! target (prepared-triangle3d-raster triangle)
                                    (prepared-triangle3d-material triangle) lights
                                    (prepared-triangle3d-owner triangle)
                                    #:write-depth? write-depth? #:blend? blend?
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
