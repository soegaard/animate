#lang racket/base

;;;
;;; Retained Racket/OpenGL Renderer
;;;

;; This is deliberately an implementation module.  It is reached only through
;; `animate/3d/opengl`, never through the headless spatial model or the normal
;; renderer protocol module.  Semantic geometry remains immutable; this file
;; owns the mutable GL host, VBO/EBO/VAO cache, shader programs and FBO cache.

(require racket/list
         racket/match
         racket/runtime-path
         ffi/vector
         "../../color-style.rkt"
         "../affine3.rkt"
         "../bounds3.rkt"
         "../camera3d.rkt"
         "../clipping3d.rkt"
         "../compiled-view3d.rkt"
         "../light3d.rkt"
         "../material3d.rkt"
         "../mesh3d.rkt"
         "../ray-plane.rkt"
         "../renderer3d.rkt"
         "../renderer3d-statistics.rkt"
         "../software-renderer3d.rkt"
         "../vec3.rkt"
         "api.rkt"
         "capabilities.rkt"
         "context-host.rkt"
         "framebuffer.rkt"
         "geometry-cache.rkt"
         "geometry-pack.rkt"
         "gl-object.rkt"
         "matrix-pack.rkt"
         "readback.rkt"
         "shader-program.rkt"
         "stroke-pass.rkt")

(provide opengl-renderer3d
         opengl-renderer3d?
         opengl-renderer3d-available?
         opengl-renderer3d-info
         opengl-renderer3d-statistics
         opengl-renderer3d-reset-statistics!
         opengl-renderer3d-release!
         opengl-renderer3d-spec
         opengl-renderer3d-spec?)

(define-runtime-path shader-directory "shaders")

;;;
;;; Public construction and configuration
;;;

(struct opengl-renderer3d-spec-value (samples cache-megabytes fallback)
  #:transparent)

(define opengl-renderer3d-spec? opengl-renderer3d-spec-value?)

; opengl-renderer3d-spec : [#:samples exact-positive-integer?]
;                          [#:cache-megabytes exact-positive-integer?]
;                          [#:fallback (or/c 'error 'software)]
;                          -> opengl-renderer3d-spec?
(define (opengl-renderer3d-spec #:samples [samples 4]
                                #:cache-megabytes [cache-megabytes 512]
                                #:fallback [fallback 'error])
  (unless (exact-positive-integer? samples)
    (raise-argument-error 'opengl-renderer3d-spec "exact-positive-integer? as #:samples" samples))
  (unless (exact-positive-integer? cache-megabytes)
    (raise-argument-error 'opengl-renderer3d-spec
                          "exact-positive-integer? as #:cache-megabytes" cache-megabytes))
  (unless (memq fallback '(error software))
    (raise-argument-error 'opengl-renderer3d-spec "(or/c 'error 'software) as #:fallback" fallback))
  (opengl-renderer3d-spec-value samples cache-megabytes fallback))

;; A preparation holds no GL handle.  Its geometry descriptors are immutable
;; author-independent data; cache lookup happens when the retained renderer
;; submits a frame, always inside its serialized context owner.
(struct opengl-preparation (compiled frame-spec unsupported-primitives)
  #:transparent)

(struct opengl-renderer3d-value
  (spec host info geometry-cache framebuffer-cache programs statistics lock released?
        fallback-renderer fallback-diagnostic
        context-creation-milliseconds shader-compilation-milliseconds
        geometry-upload-milliseconds frames)
  #:mutable
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id renderer)
     (if (opengl-renderer3d-value-host renderer) 'opengl-racket 'software))
   (define (renderer3d-capabilities renderer)
     ;; These are the capabilities of a live GL renderer.  A deliberate
     ;; software fallback delegates the reference renderer's capability report.
     (if (opengl-renderer3d-value-host renderer)
         (renderer3d-capability-set #t #t #t #t #t #t #t #t #t)
         (renderer3d-capabilities (opengl-renderer3d-value-fallback-renderer renderer))))
   (define (renderer3d-fingerprint renderer request)
     (if (opengl-renderer3d-value-host renderer)
         (vector 'animate-opengl-racket-v1
                 (opengl-renderer3d-value-spec renderer)
                 (opengl-fingerprint-info (opengl-renderer3d-value-info renderer))
                 (shader-digests (opengl-renderer3d-value-programs renderer))
                 ;; The request value ensures distinct semantic frame inputs
                 ;; never share a result cache.  No transient GLuint appears.
                 (render3d-request-compiled-view request)
                 (render3d-request-frame-spec request))
         (renderer3d-fingerprint (opengl-renderer3d-value-fallback-renderer renderer) request)))
   (define (renderer3d-prepare renderer request)
     (ensure-live-renderer 'renderer3d-prepare renderer)
     (if (opengl-renderer3d-value-host renderer)
         (prepare-opengl renderer request)
         (renderer3d-prepare (opengl-renderer3d-value-fallback-renderer renderer) request)))
   (define (renderer3d-render renderer preparation request)
     (ensure-live-renderer 'renderer3d-render renderer)
     (if (opengl-renderer3d-value-host renderer)
         (render-opengl renderer preparation request)
         (renderer3d-render (opengl-renderer3d-value-fallback-renderer renderer)
                            preparation request)))
   (define (renderer3d-release renderer)
     (opengl-renderer3d-release! renderer))])

(define opengl-renderer3d? opengl-renderer3d-value?)

; opengl-renderer3d : [opengl-renderer3d-spec?] -> renderer3d?
;; The default `#:fallback 'error` intentionally makes an explicit OpenGL
;; request fail loudly when no compatible hidden context can be made.
(define (opengl-renderer3d [spec (opengl-renderer3d-spec)])
  (unless (opengl-renderer3d-spec? spec)
    (raise-argument-error 'opengl-renderer3d "opengl-renderer3d-spec?" spec))
  (with-handlers
      ([exn?
        (lambda (exception)
          (if (eq? (opengl-renderer3d-spec-value-fallback spec) 'software)
              (opengl-renderer3d-value
               spec #f #f #f #f #f (make-renderer3d-statistics-state)
               (make-semaphore 1) #f (retained-software-renderer3d)
               (format "OpenGL unavailable; explicit software fallback: ~a"
                       (exn-message exception))
               0.0 0.0 0.0 0)
              (raise-arguments-error
               'opengl-renderer3d "a compatible OpenGL 3.2 / GLSL 1.50 context"
               "fallback-policy" (opengl-renderer3d-spec-value-fallback spec)
               "reason" (exn-message exception))))])
    (define context-start (current-inexact-milliseconds))
    (define host (make-gl-context-host))
    (define context-finished (current-inexact-milliseconds))
    (define info (probe-opengl3d-info host))
    (unless (opengl3d-info-supported? info)
      (gl-context-host-close! host)
      (raise-arguments-error 'opengl-renderer3d "the required OpenGL capabilities"
                             "diagnostics" (opengl3d-info->datum info)))
    (define shader-start (current-inexact-milliseconds))
    (define programs
      (with-handlers ([exn? (lambda (exception)
                              (gl-context-host-close! host)
                              (raise exception))])
        (make-programs host)))
    (define shader-finished (current-inexact-milliseconds))
    (opengl-renderer3d-value
     spec host info
     (make-gl-geometry-cache
      (* (opengl-renderer3d-spec-value-cache-megabytes spec) 1024 1024))
     (make-gl-framebuffer-cache)
     programs
     (make-renderer3d-statistics-state)
     (make-semaphore 1) #f #f #f
     (- context-finished context-start)
     (- shader-finished shader-start)
     0.0
     0)))

; opengl-renderer3d-available? : -> boolean?
;; Availability is intentionally a real context test, not merely “the package
;; loaded”.  It has no side effect beyond a short-lived hidden canvas.
(define (opengl-renderer3d-available?)
  (with-handlers ([exn? (lambda (_exception) #f)])
    (define host (make-gl-context-host))
    (dynamic-wind void
                  (lambda () (opengl3d-info-supported? (probe-opengl3d-info host)))
                  (lambda () (gl-context-host-close! host)))))

(define (opengl-renderer3d-info renderer)
  (ensure-opengl-renderer 'opengl-renderer3d-info renderer)
  (or (and (opengl-renderer3d-value-info renderer)
           (opengl3d-info->datum (opengl-renderer3d-value-info renderer)))
      (hasheq 'backend 'software
              'warning (opengl-renderer3d-value-fallback-diagnostic renderer))))

(define (opengl-renderer3d-statistics renderer)
  (ensure-opengl-renderer 'opengl-renderer3d-statistics renderer)
  (call-with-semaphore
   (opengl-renderer3d-value-lock renderer)
   (lambda ()
     (define base
       (renderer3d-statistics-state-snapshot
        (opengl-renderer3d-value-statistics renderer)))
     (hash-set*
      (hasheq 'backend (renderer3d-id renderer)
              'renderer-statistics base
              'frames (opengl-renderer3d-value-frames renderer)
              'context-creation-milliseconds
              (opengl-renderer3d-value-context-creation-milliseconds renderer)
              'shader-compilation-milliseconds
              (opengl-renderer3d-value-shader-compilation-milliseconds renderer)
              'geometry-upload-milliseconds
              (opengl-renderer3d-value-geometry-upload-milliseconds renderer)
              'fallback-warning (opengl-renderer3d-value-fallback-diagnostic renderer))
      'geometry-cache
      (if (opengl-renderer3d-value-geometry-cache renderer)
          (gl-geometry-cache-statistics (opengl-renderer3d-value-geometry-cache renderer))
          (hasheq))
      'framebuffer-cache
      (if (opengl-renderer3d-value-framebuffer-cache renderer)
          (gl-framebuffer-cache-statistics (opengl-renderer3d-value-framebuffer-cache renderer))
          (hasheq))))))

(define (opengl-renderer3d-reset-statistics! renderer)
  (ensure-opengl-renderer 'opengl-renderer3d-reset-statistics! renderer)
  (call-with-semaphore
   (opengl-renderer3d-value-lock renderer)
   (lambda ()
     (renderer3d-statistics-state-reset! (opengl-renderer3d-value-statistics renderer))
     (set-opengl-renderer3d-value-geometry-upload-milliseconds! renderer 0.0)
     (set-opengl-renderer3d-value-frames! renderer 0)))
  (void))

(define (opengl-renderer3d-release! renderer)
  (ensure-opengl-renderer 'opengl-renderer3d-release! renderer)
  (call-with-semaphore
   (opengl-renderer3d-value-lock renderer)
   (lambda ()
     (unless (opengl-renderer3d-value-released? renderer)
       (define host (opengl-renderer3d-value-host renderer))
       (cond [host
              ;; Geometry cache destructors require a current context, whereas
              ;; the framebuffer/program helpers schedule their own safe call.
              (gl-context-host-call
               host
               (lambda ()
                 (gl-geometry-cache-clear! (opengl-renderer3d-value-geometry-cache renderer))))
              (gl-framebuffer-cache-clear!
               (opengl-renderer3d-value-framebuffer-cache renderer) host)
              (for ([program (in-hash-values (opengl-renderer3d-value-programs renderer))])
                (gl-shader-program-delete! program host))
              (gl-context-host-close! host)]
             [else
              (renderer3d-release (opengl-renderer3d-value-fallback-renderer renderer))])
       (renderer3d-statistics-state-reset! (opengl-renderer3d-value-statistics renderer))
       (set-opengl-renderer3d-value-released?! renderer #t))))
  (void))

;;;
;;; GL program and retained geometry allocation
;;;

(define (shader-path name) (build-path shader-directory name))

(define (make-programs host)
  (hasheq 'unlit (make-gl-shader-program host (shader-path "mesh.vert")
                                        (shader-path "mesh-unlit.frag"))
          'lit (make-gl-shader-program host (shader-path "mesh.vert")
                                      (shader-path "mesh-lit.frag"))
          'depth (make-gl-shader-program host (shader-path "mesh.vert")
                                        (shader-path "depth.frag"))
          'stroke (make-gl-shader-program host (shader-path "stroke.vert")
                                         (shader-path "stroke.frag"))))

(define (shader-digests programs)
  (for/hasheq ([(name program) (in-hash programs)])
    (values name
            (vector (gl-shader-program-vertex-digest program)
                    (gl-shader-program-fragment-digest program)))))

(define (opengl-fingerprint-info info)
  (vector (opengl3d-info-vendor info)
          (opengl3d-info-renderer info)
          (opengl3d-info-version info)
          (opengl3d-info-glsl-version info)
          (opengl3d-info-profile info)))

(define (one-id ids) (u32vector-ref ids 0))

(define (delete-buffer id) (glDeleteBuffers 1 (u32vector id)))
(define (delete-vertex-array id) (glDeleteVertexArrays 1 (u32vector id)))

(define (make-gl-geometry-entry/current! host geometry variant)
  (define packed (pack-compiled-geometry3d geometry variant))
  (define vao #f)
  (define vertex-buffer #f)
  (define index-buffer #f)
  (with-handlers
      ([exn?
        (lambda (exception)
          (for ([resource (in-list (filter values (list index-buffer vertex-buffer vao)))])
            (gl-resource-delete-current! resource host))
          (raise exception))])
    (set! vao
          (gl-vertex-array (gl-context-host-identity host)
                           (one-id (glGenVertexArrays 1)) 0 #f "geometry-vao" delete-vertex-array))
    (set! vertex-buffer
          (gl-buffer (gl-context-host-identity host)
                     (one-id (glGenBuffers 1))
                     (* 4 (f32vector-length (gl-packed-geometry-vertices packed)))
                     #f "geometry-vbo" delete-buffer))
    (when (positive? (gl-packed-geometry-index-count packed))
      (set! index-buffer
            (gl-buffer (gl-context-host-identity host)
                       (one-id (glGenBuffers 1))
                       (* 4 (u32vector-length (gl-packed-geometry-indices packed)))
                       #f "geometry-ebo" delete-buffer)))
    (glBindVertexArray (gl-resource-id vao))
    (glBindBuffer GL_ARRAY_BUFFER (gl-resource-id vertex-buffer))
    (glBufferData GL_ARRAY_BUFFER (gl-resource-byte-size vertex-buffer)
                  (gl-packed-geometry-vertices packed) GL_STATIC_DRAW)
    (when index-buffer
      (glBindBuffer GL_ELEMENT_ARRAY_BUFFER (gl-resource-id index-buffer))
      (glBufferData GL_ELEMENT_ARRAY_BUFFER (gl-resource-byte-size index-buffer)
                    (gl-packed-geometry-indices packed) GL_STATIC_DRAW))
    (define stride (* 10 4))
    (glEnableVertexAttribArray 0)
    (glVertexAttribPointer 0 3 GL_FLOAT #f stride 0)
    (glEnableVertexAttribArray 1)
    (glVertexAttribPointer 1 3 GL_FLOAT #f stride (* 3 4))
    (glEnableVertexAttribArray 2)
    (glVertexAttribPointer 2 4 GL_FLOAT #f stride (* 6 4))
    (glBindVertexArray 0)
    (gl-geometry-entry
     (compiled-geometry3d-key geometry) variant vao vertex-buffer index-buffer
     (if index-buffer (gl-packed-geometry-index-count packed)
         (gl-packed-geometry-vertex-count packed))
     (gl-packed-geometry-byte-size packed) 0 (gl-context-host-identity host)
     (lambda ()
       (for ([resource (in-list (filter values (list index-buffer vertex-buffer vao)))])
         (gl-resource-delete-current! resource host))))))

;;;
;;; Protocol preparation and render passes
;;;

(define (prepare-opengl renderer request)
  (define compiled (render3d-request-compiled-view request))
  ;; Surface resources are camera-independent.  Screen-space O primitives are
  ;; prepared afresh per frame below, precisely because their clipping, dashes,
  ;; feature selection, and pixel size are camera dependent.
  (statistics-add! renderer 'spatial-compilations 1)
  (opengl-preparation compiled (render3d-request-frame-spec request) '()))

(define (render-opengl renderer preparation request)
  (cond [(not (opengl-preparation? preparation))
         ;; The matching prepare call chose the explicit software fallback.
         (renderer3d-render (ensure-software-fallback! renderer) preparation request)]
        [else
         (call-with-semaphore
          (opengl-renderer3d-value-lock renderer)
          (lambda ()
            (ensure-live-renderer 'renderer3d-render renderer)
            (define compiled (opengl-preparation-compiled preparation))
            (define frame-spec (opengl-preparation-frame-spec preparation))
            (define host (opengl-renderer3d-value-host renderer))
            ;; Allocation goes through the host separately, before the draw
            ;; transaction.  The target survives camera-only frame changes.
            (define target
              (gl-framebuffer-cache-ensure!
               (opengl-renderer3d-value-framebuffer-cache renderer)
               host (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
               (opengl-renderer3d-spec-value-samples (opengl-renderer3d-value-spec renderer))
               (opengl3d-info-maximum-samples (opengl-renderer3d-value-info renderer))))
            (define stroke-batches
              (prepare-opengl-stroke-batches compiled frame-spec))
            (define start (current-inexact-milliseconds))
            (define-values (rgba instance-count triangle-count)
              (gl-context-host-call
               host
               (lambda ()
                 (ensure-geometry-resources/current! renderer compiled)
                 (initialize-frame/current! target host compiled)
                 (define-values (opaque transparent depth-only)
                   (partition-instances compiled))
                 (for ([instance (in-list opaque)])
                   (draw-instance/current! renderer compiled frame-spec instance #f))
                 (for ([instance (in-list depth-only)])
                   (draw-instance/current! renderer compiled frame-spec instance #t))
                 (draw-stroke-batches/current! renderer stroke-batches 'hidden)
                 (draw-stroke-batches/current! renderer stroke-batches 'visible)
                 (draw-transparent/current! renderer compiled frame-spec transparent)
                 (draw-stroke-batches/current! renderer stroke-batches 'always)
                 (values (gl-framebuffer-target-read-rgba! target host)
                         (length (vector->list (compiled-view3d-instances compiled)))
                         (for/sum ([instance (in-vector (compiled-view3d-instances compiled))])
                           (triangle-count-for compiled instance))))))
            (define raster-end (current-inexact-milliseconds))
            (define argb-start (current-inexact-milliseconds))
            (define argb
              (gl-rgba-bottom-up->argb-top-down
               (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec) rgba))
            (define finished (current-inexact-milliseconds))
            (statistics-add! renderer 'instance-count instance-count)
            (statistics-add! renderer 'source-triangle-count triangle-count)
            (statistics-add! renderer 'raster-triangle-count triangle-count)
            (statistics-add! renderer 'raster-triangle-count
                             (/ (+ (opengl-stroke-batches-hidden-count stroke-batches)
                                   (opengl-stroke-batches-visible-count stroke-batches)
                                   (opengl-stroke-batches-always-count stroke-batches))
                                3))
            (statistics-add! renderer 'pixel-count (* (frame3d-spec-width frame-spec)
                                                       (frame3d-spec-height frame-spec)))
            (statistics-add! renderer 'raster-milliseconds (- raster-end start))
            (statistics-add! renderer 'readback-milliseconds (- finished argb-start))
            (set-opengl-renderer3d-value-frames! renderer
                                                  (add1 (opengl-renderer3d-value-frames renderer)))
            (renderer3d-render-result
             (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec) argb
             (hasheq 'backend 'opengl-racket
                     'samples (gl-framebuffer-target-samples target)
                     'renderer-info (opengl3d-info->datum (opengl-renderer3d-value-info renderer))
                     'geometry-cache (gl-geometry-cache-statistics
                                      (opengl-renderer3d-value-geometry-cache renderer))))))]))

(define (initialize-frame/current! target host compiled)
  (define background (color-spec->rgba-color (compiled-view3d-background compiled)
                                              'opengl-renderer3d))
  (gl-framebuffer-target-bind-draw! target host)
  (glDisable GL_SCISSOR_TEST)
  (glEnable GL_DEPTH_TEST)
  (glDepthFunc GL_LEQUAL)
  (glDepthMask #t)
  (glDisable GL_BLEND)
  (glEnable GL_CULL_FACE)
  (glCullFace GL_BACK)
  (glFrontFace GL_CCW)
  (glColorMask #t #t #t #t)
  ;; Framebuffer colour is premultiplied RGBA.  This makes the transparent pass
  ;; well-defined even when an author deliberately chooses a transparent view.
  (define background-alpha (exact->inexact (rgba-color-alpha background)))
  (glClearColor (* background-alpha (/ (rgba-color-red background) 255.0))
                (* background-alpha (/ (rgba-color-green background) 255.0))
                (* background-alpha (/ (rgba-color-blue background) 255.0))
                background-alpha)
  (glClear (bitwise-ior GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT GL_STENCIL_BUFFER_BIT)))

(define (ensure-geometry-resources/current! renderer compiled)
  (define cache (opengl-renderer3d-value-geometry-cache renderer))
  (define host (opengl-renderer3d-value-host renderer))
  (define by-key (geometry-table compiled))
  (define upload-start (current-inexact-milliseconds))
  (define uploads-before (gl-geometry-cache-uploads cache))
  (for ([instance (in-vector (compiled-view3d-instances compiled))])
    (define geometry (hash-ref by-key (compiled-instance3d-geometry-key instance)))
    (define variant
      (packed-geometry-variant-for
       (compiled-geometry3d-mesh geometry)
       (material3d-shading (compiled-instance3d-material instance))))
    (define-values (_entry hit?)
      (gl-geometry-cache-ensure!
       cache (compiled-geometry3d-key geometry) variant
       (lambda () (make-gl-geometry-entry/current! host geometry variant))))
    (statistics-add! renderer (if hit? 'geometry-cache-hits 'geometry-cache-misses) 1))
  (when (> (gl-geometry-cache-uploads cache) uploads-before)
    (set-opengl-renderer3d-value-geometry-upload-milliseconds!
     renderer
     (+ (opengl-renderer3d-value-geometry-upload-milliseconds renderer)
        (- (current-inexact-milliseconds) upload-start))))
  (statistics-add! renderer 'geometry-cache-bytes
                   (gl-geometry-cache-bytes cache)))

(define (geometry-table compiled)
  (for/hash ([geometry (in-vector (compiled-view3d-geometries compiled))])
    (values (compiled-geometry3d-key geometry) geometry)))

(define (partition-instances compiled)
  (define opaque '())
  (define transparent '())
  (define depth-only '())
  (define by-key (geometry-table compiled))
  (for ([instance (in-vector (compiled-view3d-instances compiled))])
    (cond [(eq? (compiled-instance3d-surface-mode instance) 'depth-only)
           (set! depth-only (append depth-only (list instance)))]
          [(instance-opaque? instance (hash-ref by-key (compiled-instance3d-geometry-key instance)))
           (set! opaque (append opaque (list instance)))]
          [else (set! transparent (append transparent (list instance)))]))
  (values opaque transparent depth-only))

(define (instance-opaque? instance geometry)
  (define color (material3d-color (compiled-instance3d-material instance)))
  (and (= (compiled-instance3d-opacity instance) 1)
       (= (rgba-color-alpha color) 1)
       (or (not (mesh3d-colors (compiled-geometry3d-mesh geometry)))
           (for/and ([vertex-color (in-vector (mesh3d-colors (compiled-geometry3d-mesh geometry)))])
             (= (rgba-color-alpha
                 (color-spec->rgba-color vertex-color 'opengl-renderer3d)) 1)))))

(define (draw-transparent/current! renderer compiled frame-spec transparent)
  (when (pair? transparent)
    (glEnable GL_BLEND)
    ;; Fragment shaders emit premultiplied colour. Separate factors preserve
    ;; destination alpha, unlike glBlendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA).
    (glBlendEquationSeparate GL_FUNC_ADD GL_FUNC_ADD)
    (glBlendFuncSeparate GL_ONE GL_ONE_MINUS_SRC_ALPHA
                         GL_ONE GL_ONE_MINUS_SRC_ALPHA)
    (glDepthMask #f)
    (define ordered
      (sort transparent > #:key (lambda (instance)
                                   (instance-depth compiled frame-spec instance))))
    (for ([instance (in-list ordered)])
      (draw-instance/current! renderer compiled frame-spec instance #f))
    (glDepthMask #t)
    (glDisable GL_BLEND)))

(define (draw-stroke-batches/current! renderer batches mode)
  (define program (hash-ref (opengl-renderer3d-value-programs renderer) 'stroke))
  (case mode
    [(hidden)
     (gl-draw-stroke-batch/current! program
                                    (opengl-stroke-batches-hidden batches)
                                    (opengl-stroke-batches-hidden-count batches)
                                    'hidden)]
    [(visible)
     (gl-draw-stroke-batch/current! program
                                    (opengl-stroke-batches-visible batches)
                                    (opengl-stroke-batches-visible-count batches)
                                    'test)]
    [(always)
     (gl-draw-stroke-batch/current! program
                                    (opengl-stroke-batches-always batches)
                                    (opengl-stroke-batches-always-count batches)
                                    'always)]))

(define (instance-depth compiled frame-spec instance)
  (define geometry
    (hash-ref (geometry-table compiled) (compiled-instance3d-geometry-key instance)))
  (define local (compiled-geometry3d-local-bounds geometry))
  (if (aabb3-empty? local)
      -inf.0
      (camera3d-view-depth
       (frame3d-spec-camera frame-spec)
       (affine3-apply-point (compiled-instance3d-world-transform instance)
                            (aabb3-center local)))))

(define (triangle-count-for compiled instance)
  (define geometry
    (hash-ref (geometry-table compiled) (compiled-instance3d-geometry-key instance)))
  (vector-length (mesh3d-triangles (compiled-geometry3d-mesh geometry))))

(define (draw-instance/current! renderer compiled frame-spec instance depth-only?)
  (define host (opengl-renderer3d-value-host renderer))
  (define geometry
    (hash-ref (geometry-table compiled) (compiled-instance3d-geometry-key instance)))
  (define material (compiled-instance3d-material instance))
  (define variant
    (packed-geometry-variant-for (compiled-geometry3d-mesh geometry)
                                 (material3d-shading material)))
  (define entry
    (hash-ref (gl-geometry-cache-entries (opengl-renderer3d-value-geometry-cache renderer))
              (cons (compiled-geometry3d-key geometry) variant)))
  (unless (equal? (gl-geometry-entry-context-identity entry)
                  (gl-context-host-identity host))
    (raise-arguments-error 'draw-instance/current! "geometry from the current GL context"
                           "entry" entry))
  (define program
    (cond [depth-only? (hash-ref (opengl-renderer3d-value-programs renderer) 'depth)]
          [(eq? (material3d-shading material) 'unlit)
           (hash-ref (opengl-renderer3d-value-programs renderer) 'unlit)]
          [else (hash-ref (opengl-renderer3d-value-programs renderer) 'lit)]))
  (glUseProgram (gl-shader-program-id program))
  (upload-common-uniforms/current! program frame-spec instance material
                                   (compiled-geometry3d-mesh geometry))
  (unless depth-only?
    (upload-light-uniforms/current! program frame-spec material))
  (if (material3d-double-sided? material)
      (glDisable GL_CULL_FACE)
      (glEnable GL_CULL_FACE))
  (glBindVertexArray (gl-resource-id (gl-geometry-entry-vao entry)))
  (if (gl-geometry-entry-index-buffer entry)
      (glDrawElements GL_TRIANGLES (gl-geometry-entry-index-count entry) GL_UNSIGNED_INT 0)
      (glDrawArrays GL_TRIANGLES 0 (gl-geometry-entry-index-count entry)))
  (glBindVertexArray 0)
  (glUseProgram 0))

(define (uniform/current program name)
  ;; This helper is intentionally used only while the owning context is
  ;; current.  `gl-shader-program-uniform` schedules a host call and would
  ;; deadlock inside a frame transaction.
  (hash-ref!
   (gl-shader-program-uniforms program) name
   (lambda () (glGetUniformLocation (gl-shader-program-id program) name))))

(define (uniform-mat4! program name matrix)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniformMatrix4fv location 1 #f matrix)))

(define (uniform-mat3! program name matrix)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniformMatrix3fv location 1 #f matrix)))

(define (uniform-1f! program name value)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniform1f location (exact->inexact value))))

(define (uniform-1i! program name value)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniform1i location value)))

(define (uniform-3f! program name x y z)
  (define location (uniform/current program name))
  (when (>= location 0)
    (glUniform3f location (exact->inexact x) (exact->inexact y) (exact->inexact z))))

(define (uniform-4f! program name x y z w)
  (define location (uniform/current program name))
  (when (>= location 0)
    (glUniform4f location (exact->inexact x) (exact->inexact y)
                 (exact->inexact z) (exact->inexact w))))

(define (upload-common-uniforms/current! program frame-spec instance material mesh)
  (define camera (frame3d-spec-camera frame-spec))
  (uniform-mat4! program "model" (affine3->gl-matrix (compiled-instance3d-world-transform instance)))
  (uniform-mat4! program "viewProjection"
                 (camera3d-view-projection-matrix
                  camera (/ (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec))))
  (uniform-mat3! program "normalMatrix"
                 (normal-transform->gl-matrix (compiled-instance3d-normal-transform instance)))
  (define color (material3d-color material))
  (uniform-4f! program "materialColor"
               (/ (rgba-color-red color) 255.0)
               (/ (rgba-color-green color) 255.0)
               (/ (rgba-color-blue color) 255.0)
               (rgba-color-alpha color))
  (uniform-1f! program "objectOpacity" (compiled-instance3d-opacity instance))
  (uniform-1i! program "useVertexColor" (if (mesh3d-colors mesh) 1 0))
  (upload-clip-uniforms/current! program (compiled-instance3d-clip-planes instance)))

(define (upload-clip-uniforms/current! program clips)
  (when (> (length clips) 8)
    (raise-arguments-error 'opengl-renderer3d "at most eight user clip planes"
                           "clip-plane-count" (length clips)))
  (uniform-1i! program "clipCount" (length clips))
  (for ([clip (in-list clips)] [index (in-naturals)])
    (define plane (clip-plane3d-plane clip))
    (define normal (plane3-normal plane))
    (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
    (define x (* sign (vec3-x normal)))
    (define y (* sign (vec3-y normal)))
    (define z (* sign (vec3-z normal)))
    (define offset (- (+ (* x (vec3-x (plane3-point plane)))
                         (* y (vec3-y (plane3-point plane)))
                         (* z (vec3-z (plane3-point plane))))))
    (uniform-4f! program (format "clipPlanes[~a]" index) x y z offset)))

(define (upload-light-uniforms/current! program frame-spec material)
  (when (not (eq? (material3d-shading material) 'unlit))
    (uniform-1f! program "materialAmbient" (material3d-ambient material))
    (uniform-1f! program "materialDiffuse" (material3d-diffuse material))
    (define lights (if (null? (frame3d-spec-lights frame-spec))
                       default-lights3d
                       (frame3d-spec-lights frame-spec)))
    (define-values (ambient-red ambient-green ambient-blue directions)
      (for/fold ([red 0.0] [green 0.0] [blue 0.0] [directions '()])
                ([light (in-list lights)])
        (cond [(ambient-light3d? light)
               (define color (ambient-light3d-color light))
               (values (+ red (* (ambient-light3d-intensity light)
                                 (/ (rgba-color-red color) 255.0)))
                       (+ green (* (ambient-light3d-intensity light)
                                   (/ (rgba-color-green color) 255.0)))
                       (+ blue (* (ambient-light3d-intensity light)
                                  (/ (rgba-color-blue color) 255.0)))
                       directions)]
              [else (values red green blue (append directions (list light)))])))
    (uniform-3f! program "ambientLight" ambient-red ambient-green ambient-blue)
    (define selected (take directions (min 4 (length directions))))
    (uniform-1i! program "directionalCount" (length selected))
    (for ([light (in-list selected)] [index (in-naturals)])
      (define direction (directional-light3d-direction light))
      (define color (directional-light3d-color light))
      (uniform-3f! program (format "directionalDirections[~a]" index)
                   (vec3-x direction) (vec3-y direction) (vec3-z direction))
      (uniform-3f! program (format "directionalColors[~a]" index)
                   (/ (rgba-color-red color) 255.0)
                   (/ (rgba-color-green color) 255.0)
                   (/ (rgba-color-blue color) 255.0))
      (uniform-1f! program (format "directionalIntensities[~a]" index)
                   (directional-light3d-intensity light)))))

;;;
;;; Local validation and statistics
;;;

(define (ensure-opengl-renderer who value)
  (unless (opengl-renderer3d? value)
    (raise-argument-error who "opengl-renderer3d?" value)))

(define (ensure-live-renderer who renderer)
  (ensure-opengl-renderer who renderer)
  (when (opengl-renderer3d-value-released? renderer)
    (raise-arguments-error who "an unreleased opengl-renderer3d" "renderer" renderer)))

(define (ensure-software-fallback! renderer)
  (or (opengl-renderer3d-value-fallback-renderer renderer)
      (let ([fallback (retained-software-renderer3d)])
        (set-opengl-renderer3d-value-fallback-renderer! renderer fallback)
        (set-opengl-renderer3d-value-fallback-diagnostic!
         renderer "OpenGL strokes/markers are not yet enabled; explicit software fallback selected")
        fallback)))

(define (statistics-add! renderer field value)
  (renderer3d-statistics-state-add!
   (opengl-renderer3d-value-statistics renderer) field value))
