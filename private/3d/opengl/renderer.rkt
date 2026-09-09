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
         racket/set
         ffi/vector
         "../../color-style.rkt"
         "../../render-color-context.rkt"
         "../affine3.rkt"
         "../bounds3.rkt"
         "../camera3d.rkt"
         "../color-resolution3d.rkt"
         "../color-space3d.rkt"
         "../clipping3d.rkt"
         "../compiled-view3d.rkt"
         "../light-attenuation3d.rkt"
         "../light3d.rkt"
         "../material3d.rkt"
         "../mesh3d.rkt"
         "../projection3d.rkt"
         "../ray-plane.rkt"
         "../renderer3d.rkt"
         "../renderer3d-statistics.rkt"
         "../shadow-map3d.rkt"
         "../shadow3d.rkt"
         "../software-renderer3d.rkt"
         "../vec3.rkt"
         "api.rkt"
         "billboard-pass.rkt"
         "capabilities.rkt"
         "context-host.rkt"
         "framebuffer.rkt"
         "geometry-cache.rkt"
         "geometry-pack.rkt"
         "limits.rkt"
         "gl-object.rkt"
         "matrix-pack.rkt"
         "readback.rkt"
         "shadow-cache.rkt"
         "shadow-framebuffer.rkt"
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
(struct opengl-preparation (compiled frame-spec unsupported-primitives color-context)
  #:transparent)

(struct opengl-renderer3d-value
  (spec host info geometry-cache framebuffer-cache shadow-cache programs fallback-shadow-texture statistics lock released?
        fallback-renderer fallback-diagnostic
        context-creation-milliseconds shader-compilation-milliseconds
        geometry-upload-milliseconds frames)
  #:mutable
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id renderer)
     (if (opengl-renderer3d-value-host renderer) 'opengl-racket 'software))
   (define (renderer3d-capabilities-of renderer)
     ;; These are the capabilities of a live GL renderer.  A deliberate
     ;; software fallback delegates the reference renderer's capability report.
     (if (opengl-renderer3d-value-host renderer)
         (opengl-capabilities renderer)
         (renderer3d-capabilities-of
          (opengl-renderer3d-value-fallback-renderer renderer))))
   (define (renderer3d-fingerprint renderer request)
     (if (opengl-renderer3d-value-host renderer)
         (vector 'animate-opengl-racket-v1
                 (opengl-renderer3d-value-spec renderer)
                 (opengl-fingerprint-info (opengl-renderer3d-value-info renderer))
                 (shader-digests (opengl-renderer3d-value-programs renderer))
                 ;; The request value ensures distinct semantic frame inputs
                 ;; never share a result cache.  No transient GLuint appears.
                 (render3d-request-compiled-view request)
                 (render3d-request-frame-spec request)
                 (render-color-context-appearance-fingerprint
                  (render3d-request-color-context request))
                 (render-color-context-resolver-version
                  (render3d-request-color-context request)))
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

;; The initial GL shaders have fixed uniform arrays. Keeping those limits in
;; the renderer declaration makes an over-limit project fail before submission
;; instead of silently drawing only a prefix of its authored lights or clips.
(define (opengl-capabilities renderer)
  (define info (opengl-renderer3d-value-info renderer))
  (define spec (opengl-renderer3d-value-spec renderer))
  (renderer3d-capabilities
   (seteq 'opaque-triangles
          'perspective
          'orthographic
          'depth-buffer
          'flat-shading
          'smooth-shading
          'transparency
          'clipping-planes
          'screen-strokes
          'linear-depth
          'ambient-light
          'directional-light
          'point-light
          'spot-light
          'directional-shadow
          'spot-shadow)
   (hash-set
    (hash-set (opengl3d-capability-limits)
              'maximum-shadow-map-size 4096)
    ;; A non-multisample framebuffer remains valid at one sample even when
    ;; GL_MAX_SAMPLES is unavailable or reports zero.
    'maximum-samples (max 1 (opengl3d-info-maximum-samples info)))
   (hasheq 'backend 'opengl-racket
           'requested-samples (opengl-renderer3d-spec-value-samples spec)
           'shader-limits opengl3d-limits
           'unsupported-features
           '(wireframe object-id specular emission))))

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
               spec #f #f #f #f #f #f #f (make-renderer3d-statistics-state)
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
    ;; A GLSL sampler has a default texture unit even when a zero count makes
    ;; its branch unreachable.  Keep one type-correct depth texture around so
    ;; an unused shadow sampler never aliases a colour texture on strict macOS
    ;; drivers.  It is not a shadow map and is never counted as one.
    (define fallback-shadow-texture #f)
    (define programs
      (with-handlers ([exn? (lambda (exception)
                              (when fallback-shadow-texture
                                (gl-context-host-call
                                 host
                                 (lambda ()
                                   (gl-resource-delete-current!
                                    fallback-shadow-texture host))))
                              (gl-context-host-close! host)
                              (raise exception))])
        (set! fallback-shadow-texture
              (gl-context-host-call host
                                    (lambda ()
                                      (make-fallback-shadow-texture/current! host))))
        (make-programs host)))
    (define shader-finished (current-inexact-milliseconds))
    (opengl-renderer3d-value
     spec host info
     (make-gl-geometry-cache
      (* (opengl-renderer3d-spec-value-cache-megabytes spec) 1024 1024))
     (make-gl-framebuffer-cache)
     (make-gl-shadow-cache
      #:max-bytes (* (opengl-renderer3d-spec-value-cache-megabytes spec) 1024 1024))
     programs
     fallback-shadow-texture
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
          (hasheq))
      'shadow-cache
      (if (opengl-renderer3d-value-shadow-cache renderer)
          (gl-shadow-cache-statistics (opengl-renderer3d-value-shadow-cache renderer))
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
                 (gl-geometry-cache-clear! (opengl-renderer3d-value-geometry-cache renderer))
                 (gl-shadow-cache-clear/current!
                  (opengl-renderer3d-value-shadow-cache renderer)
                  (lambda (target) (gl-shadow-target-delete/current! target host)))))
              (gl-context-host-call
               host
               (lambda ()
                 (define fallback-shadow-texture
                   (opengl-renderer3d-value-fallback-shadow-texture renderer))
                 (when fallback-shadow-texture
                   (gl-resource-delete-current! fallback-shadow-texture host))))
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
  (define fragment-preamble (opengl3d-shader-defines))
  (define (make-program vertex fragment)
    (make-gl-shader-program host (shader-path vertex) (shader-path fragment)
                            #:fragment-preamble fragment-preamble))
  (hasheq 'unlit (make-program "mesh.vert" "mesh-unlit.frag")
          'lit (make-program "mesh.vert" "mesh-lit.frag")
          'depth (make-program "mesh.vert" "depth.frag")
          'shadow (make-program "shadow.vert" "shadow.frag")
          'stroke (make-gl-shader-program host (shader-path "stroke.vert")
                                         (shader-path "stroke.frag"))
          'billboard (make-gl-shader-program
                      host (shader-path "billboard.vert") (shader-path "billboard.frag")
                      #:attributes '(("position" . 0) ("uv" . 1)))))

;; A live shader program validates sampler types before it proves that an
;; array count is zero.  This immutable 1×1 comparison texture gives every
;; inactive shadow sampler a valid binding; authored shadow maps still replace
;; their selected slots during each mesh draw.
(define (make-fallback-shadow-texture/current! host)
  (define texture-id (u32vector-ref (glGenTextures 1) 0))
  (define texture
    (gl-texture (gl-context-host-identity host) texture-id 4 #f
                "fallback-shadow-depth"
                (lambda (id) (glDeleteTextures 1 (u32vector id)))))
  (with-handlers ([exn? (lambda (exception)
                          (when (positive? texture-id)
                            (glDeleteTextures 1 (u32vector texture-id)))
                          (raise exception))])
    (glActiveTexture GL_TEXTURE0)
    (glBindTexture GL_TEXTURE_2D texture-id)
    (glTexImage2D GL_TEXTURE_2D 0 GL_DEPTH_COMPONENT24 1 1 0
                  GL_DEPTH_COMPONENT GL_FLOAT #f)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_BASE_LEVEL 0)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAX_LEVEL 0)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_COMPARE_MODE GL_COMPARE_REF_TO_TEXTURE)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_COMPARE_FUNC GL_LEQUAL)
    (glBindTexture GL_TEXTURE_2D 0)
    texture))

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

(define (make-gl-geometry-entry/current! host geometry variant color-context)
  (define packed (pack-compiled-geometry3d geometry variant
                                             #:color-context color-context))
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
     (gl-packed-geometry-key packed) variant vao vertex-buffer index-buffer
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
  (renderer3d-require-request-capabilities renderer request)
  (define compiled (render3d-request-compiled-view request))
  ;; Surface resources are camera-independent.  Screen-space O primitives are
  ;; prepared afresh per frame below, precisely because their clipping, dashes,
  ;; feature selection, and pixel size are camera dependent.
  (statistics-add! renderer 'spatial-compilations 1)
  (opengl-preparation compiled (render3d-request-frame-spec request) '()
                      (render3d-request-color-context request)))

(define (render-opengl renderer preparation request)
  (cond [(not (opengl-preparation? preparation))
         ;; The matching prepare call chose the explicit software fallback.
         (renderer3d-render (ensure-software-fallback! renderer) preparation request)]
        [else
         (call-with-semaphore
          (opengl-renderer3d-value-lock renderer)
          (lambda ()
            (ensure-live-renderer 'renderer3d-render renderer)
            (define requested (render3d-request-attachments request))
            (for ([attachment (in-list requested)]
                  #:when (memq attachment '(object-id normal)))
              (raise-arguments-error
               'renderer3d-render
               "an OpenGL renderer supporting every requested attachment"
               "unsupported-attachment" attachment
               "renderer" 'opengl-racket))
            (define compiled (opengl-preparation-compiled preparation))
            (define frame-spec (opengl-preparation-frame-spec preparation))
            (define color-context (opengl-preparation-color-context preparation))
            (unless (and (= (render-color-context-resolver-version color-context)
                            (render-color-context-resolver-version
                             (render3d-request-color-context request)))
                         (equal? (render-color-context-appearance-fingerprint color-context)
                                 (render-color-context-appearance-fingerprint
                                  (render3d-request-color-context request))))
              (raise-arguments-error
               'renderer3d-render
               "an OpenGL preparation made for the request's color context"
               "preparation-appearance"
               (render-color-context-appearance-fingerprint color-context)
               "request-appearance"
               (render-color-context-appearance-fingerprint
                (render3d-request-color-context request))))
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
              (parameterize ([current-render-color-context color-context])
                (prepare-opengl-stroke-batches compiled frame-spec)))
            (define billboards
              (parameterize ([current-render-color-context color-context])
                (prepare-opengl-billboards compiled frame-spec)))
            (define start (current-inexact-milliseconds))
            (define-values (linear-rgba raw-depth instance-count triangle-count)
              (gl-context-host-call
               host
               (lambda ()
                 (parameterize ([current-render-color-context color-context])
                  (ensure-geometry-resources/current! renderer compiled)
                 ;; The map pass is intentionally before the main framebuffer
                 ;; initialization. It owns its depth-only FBO and restores
                 ;; colour/depth/cull state before this ordinary frame begins.
                 (define shadow-samples
                   (prepare-gl-shadow-maps/current! renderer compiled frame-spec))
                 (initialize-frame/current! target host compiled)
                 (define-values (opaque transparent depth-only)
                   (partition-instances compiled))
                 (for ([instance (in-list opaque)])
                   (draw-instance/current! renderer compiled frame-spec instance #f
                                           #:shadow-samples shadow-samples))
                 (for ([instance (in-list depth-only)])
                   (draw-instance/current! renderer compiled frame-spec instance #t))
                 (draw-stroke-batches/current! renderer stroke-batches 'hidden)
                 (draw-billboards/current! renderer billboards 'hidden frame-spec)
                 (draw-stroke-batches/current! renderer stroke-batches 'visible)
                 (draw-billboards/current! renderer billboards 'test frame-spec)
                 (draw-transparent/current! renderer compiled frame-spec transparent)
                 (draw-stroke-batches/current! renderer stroke-batches 'always)
                 (draw-billboards/current! renderer billboards 'always frame-spec)
                  (values (gl-framebuffer-target-read-linear-rgba! target host)
                          (and (member 'linear-depth requested)
                               (gl-framebuffer-target-read-depth! target host))
                          (length (vector->list (compiled-view3d-instances compiled)))
                          (for/sum ([instance (in-vector (compiled-view3d-instances compiled))])
                            (triangle-count-for compiled instance)))))))
            (define raster-end (current-inexact-milliseconds))
            (define argb-start (current-inexact-milliseconds))
            (define argb
              (gl-linear-rgba-bottom-up->argb-top-down
               (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec) linear-rgba
               (compiled-view3d-tone-map compiled)))
            (define linear-depth
              (and raw-depth
                   (gl-depth-bottom-up->linear-top-down
                    raw-depth (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
                    (frame3d-spec-camera frame-spec))))
            (define finished (current-inexact-milliseconds))
            (statistics-add! renderer 'instance-count instance-count)
            (statistics-add! renderer 'source-triangle-count triangle-count)
            (statistics-add! renderer 'raster-triangle-count triangle-count)
            (statistics-add! renderer 'raster-triangle-count
                             (/ (+ (opengl-stroke-batches-hidden-count stroke-batches)
                                   (opengl-stroke-batches-visible-count stroke-batches)
                                   (opengl-stroke-batches-always-count stroke-batches))
                                3))
            (statistics-add! renderer 'raster-triangle-count (* 2 (length billboards)))
            (statistics-add! renderer 'pixel-count (* (frame3d-spec-width frame-spec)
                                                       (frame3d-spec-height frame-spec)))
            (statistics-add! renderer 'raster-milliseconds (- raster-end start))
            (statistics-add! renderer 'readback-milliseconds (- finished argb-start))
            (set-opengl-renderer3d-value-frames! renderer
                                                  (add1 (opengl-renderer3d-value-frames renderer)))
            (define artifact
              (renderer3d-frame-artifact
               (frame3d-spec-width frame-spec) (frame3d-spec-height frame-spec)
               (and (member 'color requested) argb)
               linear-depth #f #f (frame3d-spec-camera frame-spec)
               (hasheq 'backend 'opengl-racket
                       'samples (gl-framebuffer-target-samples target)
                       'attachments requested
                       'renderer-info (opengl3d-info->datum (opengl-renderer3d-value-info renderer))
                       'geometry-cache (gl-geometry-cache-statistics
                                        (opengl-renderer3d-value-geometry-cache renderer)))))
            (unless (renderer3d-attachment-set-satisfies?
                     (renderer3d-frame-artifact-attachments artifact) requested)
              (raise-arguments-error 'renderer3d-render
                                     "an artifact satisfying requested OpenGL attachments"
                                     "requested" requested
                                     "available" (renderer3d-frame-artifact-attachments artifact)))
            (renderer3d-render-result artifact)))]))

(define (initialize-frame/current! target host compiled)
  (define background
    (rgba-srgb->linear
     (resolve-color-in-context (compiled-view3d-background compiled)
                               (current-or-default-render-color-context))))
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
  (define background-alpha (exact->inexact (linear-rgba3d-alpha background)))
  ;; Racket 9.3's OpenGL FFI contracts require actual flonums.  Exact zero is
  ;; common for black backgrounds, so normalize the multiplied channels too.
  (glClearColor (exact->inexact (* background-alpha (linear-rgba3d-red background)))
                (exact->inexact (* background-alpha (linear-rgba3d-green background)))
                (exact->inexact (* background-alpha (linear-rgba3d-blue background)))
                background-alpha)
  (glClear (bitwise-ior GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT GL_STENCIL_BUFFER_BIT)))

;; Hardware depth is non-linear for perspective cameras and arrives in
;; bottom-up framebuffer order. Convert it once at the renderer boundary so
;; projected labels and inspection compare the same positive view-space depth
;; that the software renderer records.
(define (gl-depth-bottom-up->linear-top-down raw width height camera)
  (unless (= (vector-length raw) (* width height))
    (raise-arguments-error 'gl-depth-bottom-up->linear-top-down
                           "depth data matching dimensions"
                           "depth-count" (vector-length raw)
                           "dimensions" (vector width height)))
  (define near (exact->inexact (camera3d-near camera)))
  (define far (exact->inexact (camera3d-far camera)))
  (define perspective?
    (perspective-projection3d? (camera3d-projection camera)))
  (vector->immutable-vector
   (for/vector ([index (in-range (* width height))])
     (define x (remainder index width))
     (define y (quotient index width))
     (define raw-index (+ x (* (- (sub1 height) y) width)))
     (define depth (vector-ref raw raw-index))
     ;; Clear depth is one. Keep it as +inf.0 so it cannot occlude a label.
     (cond [(>= depth 1.0) +inf.0]
           [perspective?
            (/ (* near far) (- far (* depth (- far near))))]
           [else (+ near (* depth (- far near)))]))))

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
    (define resource-key
      (packed-geometry-appearance-key
       geometry (current-or-default-render-color-context)))
    (define-values (_entry hit?)
      (gl-geometry-cache-ensure!
       cache resource-key variant
       (lambda () (make-gl-geometry-entry/current!
                   host geometry variant (current-or-default-render-color-context)))))
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

;; An entry stays valid across main-camera motion because its key contains only
;; depth-map inputs: eligible caster geometry/placement/policy, shadow-light
;; pose/settings, and the selected world-space bounds. The target itself is
;; owned by the bounded cache and therefore never enters an authored view.
(struct gl-shadow-sample (light-id target camera settings bounds) #:transparent)

(define (prepare-gl-shadow-maps/current! renderer compiled frame-spec)
  (define lights (effective-frame-lights frame-spec))
  (define caster-bounds (compiled-shadow-caster-bounds compiled))
  (cond
    [(aabb3-empty? caster-bounds) '()]
    [else
     (define descriptors
       (filter (lambda (light) (light3d-shadow light)) lights))
     (unless (<= (length descriptors) (opengl3d-limit 'shadow-maps))
       (raise-arguments-error 'opengl-renderer3d
                              "a shadow count within the current shader's fixed limit"
                              "shadow-light-count" (length descriptors)))
     (for/list ([light (in-list descriptors)])
       (define shadow (light3d-shadow light))
       (define settings (shadow3d-settings shadow))
       (define bounds (or (shadow-settings3d-bounds settings) caster-bounds))
       (define camera (shadow-light-camera3d light settings bounds))
       (define key (opengl-shadow-map-key compiled light settings bounds))
       (define cache (opengl-renderer3d-value-shadow-cache renderer))
       (define map-size (shadow-settings3d-map-size settings))
       (define-values (entry _hit?)
         (gl-shadow-cache-ensure/current!
          cache key (* map-size map-size 4)
          (lambda ()
            (define target (make-gl-shadow-target/current!
                            (opengl-renderer3d-value-host renderer) map-size))
            (with-handlers
                ([exn? (lambda (exception)
                         (gl-shadow-target-delete/current!
                          target (opengl-renderer3d-value-host renderer))
                         (raise exception))])
              (render-gl-shadow-map/current! renderer compiled camera target)
              target))
          (lambda (target)
            (gl-shadow-target-delete/current! target
                                              (opengl-renderer3d-value-host renderer)))))
       (gl-shadow-sample (light3d-id light) (gl-shadow-cache-entry-target entry)
                         camera settings bounds))]))

(define (effective-frame-lights frame-spec)
  (resolve-lights3d
   (if (null? (frame3d-spec-lights frame-spec))
       default-lights3d
       (frame3d-spec-lights frame-spec))
   (current-or-default-render-color-context)))

(define (compiled-shadow-caster-bounds compiled)
  (define by-key (geometry-table compiled))
  (for/fold ([result aabb3-empty])
            ([instance (in-vector (compiled-view3d-instances compiled))])
    (define geometry (hash-ref by-key (compiled-instance3d-geometry-key instance)))
    (if (shadow-caster-instance? instance geometry)
        (aabb3-union
         result
         (aabb3-transform (compiled-geometry3d-local-bounds geometry)
                          (compiled-instance3d-world-transform instance)))
        result)))

(define (shadow-caster-instance? instance geometry)
  (and (material3d-casts-shadow? (compiled-instance3d-material instance))
       (instance-opaque? instance geometry)))

(define (opengl-shadow-map-key compiled light settings bounds)
  (vector-immutable
   'animate-opengl-shadow-map-v1
   (for/list ([instance (in-vector (compiled-view3d-instances compiled))])
     (define material (compiled-instance3d-material instance))
     (vector-immutable
      (compiled-instance3d-geometry-key instance)
      (compiled-instance3d-world-transform instance)
      (compiled-instance3d-clip-planes instance)
      (compiled-instance3d-surface-mode instance)
      (compiled-instance3d-opacity instance)
      (material3d-casts-shadow? material)
      (material3d-receives-shadow? material)
      (material3d-double-sided? material)
      (rgba-color-alpha
       (resolve-color-in-context
        (material3d-color material)
        (current-or-default-render-color-context)))))
   (if (directional-light3d? light)
       (vector-immutable 'directional (directional-light3d-direction light))
       (vector-immutable 'spot (spot-light3d-position light)
                         (spot-light3d-direction light)
                         (spot-light3d-range light)
                         (spot-light3d-outer-angle light)))
   settings bounds))

(define (render-gl-shadow-map/current! renderer compiled camera target)
  (define host (opengl-renderer3d-value-host renderer))
  (gl-shadow-target-bind-draw/current! target host)
  (glDisable GL_SCISSOR_TEST)
  (glColorMask #f #f #f #f)
  (glEnable GL_DEPTH_TEST)
  (glDepthFunc GL_LEQUAL)
  (glDepthMask #t)
  (glDisable GL_BLEND)
  (glEnable GL_CULL_FACE)
  (glCullFace GL_BACK)
  (glFrontFace GL_CCW)
  (glEnable GL_POLYGON_OFFSET_FILL)
  (glPolygonOffset 1.0 1.0)
  (glClear (bitwise-ior GL_DEPTH_BUFFER_BIT))
  (define map-frame (frame3d-spec camera '()
                                  (gl-shadow-target-size target)
                                  (gl-shadow-target-size target)))
  (define by-key (geometry-table compiled))
  (for ([instance (in-vector (compiled-view3d-instances compiled))])
    (define geometry (hash-ref by-key (compiled-instance3d-geometry-key instance)))
    (when (shadow-caster-instance? instance geometry)
      (draw-shadow-instance/current! renderer compiled map-frame instance)))
  ;; The main pass explicitly initializes all state it uses, but resetting the
  ;; exceptional colour mask and polygon offset here keeps the depth pass safe
  ;; for any future intermediate pass as well.
  (glDisable GL_POLYGON_OFFSET_FILL)
  (glColorMask #t #t #t #t)
  (glBindVertexArray 0)
  (glUseProgram 0)
  (glBindFramebuffer GL_FRAMEBUFFER 0))

(define (draw-shadow-instance/current! renderer compiled frame-spec instance)
  (define host (opengl-renderer3d-value-host renderer))
  (define geometry
    (hash-ref (geometry-table compiled) (compiled-instance3d-geometry-key instance)))
  (define material (compiled-instance3d-material instance))
  (define variant
    (packed-geometry-variant-for (compiled-geometry3d-mesh geometry)
                                 (material3d-shading material)))
  (define entry
    (hash-ref (gl-geometry-cache-entries (opengl-renderer3d-value-geometry-cache renderer))
              (cons (packed-geometry-appearance-key
                     geometry (current-or-default-render-color-context))
                    variant)))
  (gl-resource-check-current! (gl-geometry-entry-vao entry) host)
  (define program (hash-ref (opengl-renderer3d-value-programs renderer) 'shadow))
  (glUseProgram (gl-shader-program-id program))
  (uniform-mat4! program "model" (affine3->gl-matrix (compiled-instance3d-world-transform instance)))
  (uniform-mat4! program "viewProjection"
                 (camera3d-view-projection-matrix (frame3d-spec-camera frame-spec) 1))
  (upload-clip-uniforms/current! program (compiled-instance3d-clip-planes instance))
  (if (material3d-double-sided? material)
      (glDisable GL_CULL_FACE)
      (glEnable GL_CULL_FACE))
  (glBindVertexArray (gl-resource-id (gl-geometry-entry-vao entry)))
  (if (gl-geometry-entry-index-buffer entry)
      (glDrawElements GL_TRIANGLES (gl-geometry-entry-index-count entry) GL_UNSIGNED_INT 0)
      (glDrawArrays GL_TRIANGLES 0 (gl-geometry-entry-index-count entry)))
  (glBindVertexArray 0)
  (glUseProgram 0))

(define (instance-opaque? instance geometry)
  (define color
    (resolve-color-in-context
     (material3d-color (compiled-instance3d-material instance))
     (current-or-default-render-color-context)))
  (and (= (compiled-instance3d-opacity instance) 1)
       (= (rgba-color-alpha color) 1)
       (or (not (mesh3d-colors (compiled-geometry3d-mesh geometry)))
           (for/and ([vertex-color (in-vector (mesh3d-colors (compiled-geometry3d-mesh geometry)))])
             (= (rgba-color-alpha
                 (resolve-color-in-context
                  vertex-color (current-or-default-render-color-context))) 1)))))

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

(define (draw-billboards/current! renderer billboards mode frame-spec)
  (gl-draw-billboards/current!
   (hash-ref (opengl-renderer3d-value-programs renderer) 'billboard)
   billboards mode
   (frame3d-spec-camera frame-spec)
   (frame3d-spec-width frame-spec)
   (frame3d-spec-height frame-spec)))

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

(define (draw-instance/current! renderer compiled frame-spec instance depth-only?
                                #:shadow-samples [shadow-samples '()])
  (define host (opengl-renderer3d-value-host renderer))
  (define geometry
    (hash-ref (geometry-table compiled) (compiled-instance3d-geometry-key instance)))
  (define material
    (resolve-material3d (compiled-instance3d-material instance)
                        (current-or-default-render-color-context)))
  (define variant
    (packed-geometry-variant-for (compiled-geometry3d-mesh geometry)
                                 (material3d-shading material)))
  (define entry
    (hash-ref (gl-geometry-cache-entries (opengl-renderer3d-value-geometry-cache renderer))
              (cons (packed-geometry-appearance-key
                     geometry (current-or-default-render-color-context))
                    variant)))
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
    (upload-light-uniforms/current!
     program frame-spec material shadow-samples
     (opengl-renderer3d-value-fallback-shadow-texture renderer)))
  (if (material3d-double-sided? material)
      (glDisable GL_CULL_FACE)
      (glEnable GL_CULL_FACE))
  (glBindVertexArray (gl-resource-id (gl-geometry-entry-vao entry)))
  (if (gl-geometry-entry-index-buffer entry)
      (glDrawElements GL_TRIANGLES (gl-geometry-entry-index-count entry) GL_UNSIGNED_INT 0)
      (glDrawArrays GL_TRIANGLES 0 (gl-geometry-entry-index-count entry)))
  ;; Shadow-map bindings deliberately remain live until a later pass replaces
  ;; them. OpenGL captures the state for this draw, but macOS may defer the
  ;; depth texture's residency validation until after Racket returns from the
  ;; callback; unbinding immediately here can produce a false zero-texture
  ;; diagnostic. Every mesh draw explicitly binds its maps (or sets count 0),
  ;; and billboard/depth/stroke passes bind their own resources, so this does
  ;; not introduce a cross-pass rendering dependency.
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

(define (uniform-2f! program name x y)
  (define location (uniform/current program name))
  (when (>= location 0)
    (glUniform2f location (exact->inexact x) (exact->inexact y))))

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
  (define emission (material3d-emission material))
  (uniform-3f! program "materialEmission"
               (/ (rgba-color-red emission) 255.0)
               (/ (rgba-color-green emission) 255.0)
               (/ (rgba-color-blue emission) 255.0))
  (uniform-1f! program "materialEmissionStrength"
               (material3d-emission-strength material))
  (upload-clip-uniforms/current! program (compiled-instance3d-clip-planes instance)))

(define (upload-clip-uniforms/current! program clips)
  (when (> (length clips) (opengl3d-limit 'clip-planes))
    (raise-arguments-error 'opengl-renderer3d
                           "a clip-plane count within the current shader's fixed limit"
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

(struct gl-light-record
  (id kind direction position color intensity attenuation-mode attenuation-a attenuation-b attenuation-c
        attenuation-cutoff range inner-angle outer-angle)
  #:transparent)

;; The mesh shader consumes one ordered stream instead of independently packed
;; arrays for each light kind.  Consequently a frame's non-ambient lights are
;; accumulated in the author's list order, while the published per-kind limits
;; still reject a frame before a fixed GPU array can truncate it.
(define (pack-gl-lights lights)
  (define-values (ambient-red ambient-green ambient-blue records)
    (for/fold ([red 0.0] [green 0.0] [blue 0.0] [reversed-records '()])
              ([light (in-list lights)])
      (cond
        [(ambient-light3d? light)
         (define linear (rgba-srgb->linear (ambient-light3d-color light)))
         (values (+ red (* (ambient-light3d-intensity light) (linear-rgba3d-red linear)))
                 (+ green (* (ambient-light3d-intensity light) (linear-rgba3d-green linear)))
                 (+ blue (* (ambient-light3d-intensity light) (linear-rgba3d-blue linear)))
                 reversed-records)]
        [(directional-light3d? light)
         (values red green blue
                 (cons (gl-light-record
                        (directional-light3d-id light)
                        0 (directional-light3d-direction light) origin3
                        (directional-light3d-color light) (directional-light3d-intensity light)
                        0 1 0 0 -1 -1 0 0)
                       reversed-records))]
        [(point-light3d? light)
         (values red green blue
                 (cons (finite-light->gl-record
                        (point-light3d-id light)
                        1 (point-light3d-position light) origin3
                        (point-light3d-color light) (point-light3d-intensity light)
                        (point-light3d-attenuation light) (point-light3d-range light) 0 0)
                       reversed-records))]
        [(spot-light3d? light)
         (values red green blue
                 (cons (finite-light->gl-record
                        (spot-light3d-id light)
                        2 (spot-light3d-position light) (spot-light3d-direction light)
                        (spot-light3d-color light) (spot-light3d-intensity light)
                        (spot-light3d-attenuation light) (spot-light3d-range light)
                        (spot-light3d-inner-angle light) (spot-light3d-outer-angle light))
                       reversed-records))]
        [else
         (raise-argument-error 'opengl-renderer3d "light3d?" light)])))
  (values ambient-red ambient-green ambient-blue (reverse records)))

(define (finite-light->gl-record id kind position direction color intensity attenuation range inner outer)
  (define parameters (light-attenuation3d-parameters attenuation))
  (define-values (mode a b c cutoff)
    (case (light-attenuation3d-mode attenuation)
      [(constant)
       (values 0 (hash-ref parameters 'factor) 0 0 -1)]
      [(inverse-square)
       (values 1 0 0 (hash-ref parameters 'reference-distance)
               (or (hash-ref parameters 'cutoff) -1))]
      [(polynomial)
       (values 2 (hash-ref parameters 'constant) (hash-ref parameters 'linear)
               (hash-ref parameters 'quadratic) (or (hash-ref parameters 'cutoff) -1))]))
  ;; Inverse-square uses the `c` slot as its named reference distance; the
  ;; shader's polynomial mode uses all of a, b and c.
  (gl-light-record id kind direction position color intensity mode a b c cutoff
                   (or range -1) inner outer))

(define (check-gl-light-limits records)
  (define directional-count (count (lambda (record) (= (gl-light-record-kind record) 0)) records))
  (define point-count (count (lambda (record) (= (gl-light-record-kind record) 1)) records))
  (define spot-count (count (lambda (record) (= (gl-light-record-kind record) 2)) records))
  (for ([actual (in-list (list directional-count point-count spot-count))]
        [maximum (in-list (list (opengl3d-limit 'directional-lights)
                                (opengl3d-limit 'point-lights)
                                (opengl3d-limit 'spot-lights)))]
        [kind (in-list '(directional point spot))])
    (unless (<= actual maximum)
      (raise-arguments-error 'opengl-renderer3d
                             "a light count within the current shader's fixed limit"
                             "light-kind" kind "count" actual "maximum" maximum)))
  (unless (<= (length records)
              (hash-ref (opengl3d-capability-limits) 'non-ambient-lights))
    (raise-arguments-error 'opengl-renderer3d
                           "a non-ambient light count within the current shader's fixed limit"
                           "light-count" (length records)))
  (void))

(define (upload-light-uniforms/current! program frame-spec material shadow-samples
                                        fallback-shadow-texture)
  (when (not (eq? (material3d-shading material) 'unlit))
    (uniform-1f! program "materialAmbient" (material3d-ambient material))
    (uniform-1f! program "materialDiffuse" (material3d-diffuse material))
    (uniform-1f! program "materialSpecular" (material3d-specular material))
    (define specular-color (material3d-specular-color material))
    (uniform-3f! program "materialSpecularColor"
                 (/ (rgba-color-red specular-color) 255.0)
                 (/ (rgba-color-green specular-color) 255.0)
                 (/ (rgba-color-blue specular-color) 255.0))
    (uniform-1f! program "materialSpecularExponent"
                 (material3d-specular-exponent material))
    (uniform-1i! program "materialLighting"
                 (if (eq? (material3d-lighting material) 'blinn-phong) 1 0))
    (define camera-position (camera3d-position (frame3d-spec-camera frame-spec)))
    (uniform-3f! program "cameraPosition"
                 (vec3-x camera-position) (vec3-y camera-position) (vec3-z camera-position))
    (define lights (if (null? (frame3d-spec-lights frame-spec))
                       default-lights3d
                       (frame3d-spec-lights frame-spec)))
    (define-values (ambient-red ambient-green ambient-blue selected)
      (pack-gl-lights lights))
    (uniform-3f! program "ambientLight" ambient-red ambient-green ambient-blue)
    (check-gl-light-limits selected)
    (uniform-1i! program "nonAmbientLightCount" (length selected))
    (for ([light (in-list selected)] [index (in-naturals)])
      (define direction (gl-light-record-direction light))
      (define position (gl-light-record-position light))
      (define color (gl-light-record-color light))
      (uniform-1i! program (format "nonAmbientLightKinds[~a]" index)
                   (gl-light-record-kind light))
      (uniform-3f! program (format "nonAmbientLightDirections[~a]" index)
                   (vec3-x direction) (vec3-y direction) (vec3-z direction))
      (uniform-3f! program (format "nonAmbientLightPositions[~a]" index)
                   (vec3-x position) (vec3-y position) (vec3-z position))
      (uniform-3f! program (format "nonAmbientLightColors[~a]" index)
                   (/ (rgba-color-red color) 255.0)
                   (/ (rgba-color-green color) 255.0)
                   (/ (rgba-color-blue color) 255.0))
      (uniform-1f! program (format "nonAmbientLightIntensities[~a]" index)
                   (gl-light-record-intensity light))
      (uniform-1i! program (format "nonAmbientLightAttenuationModes[~a]" index)
                   (gl-light-record-attenuation-mode light))
      (uniform-3f! program (format "nonAmbientLightAttenuationABC[~a]" index)
                   (gl-light-record-attenuation-a light)
                   (gl-light-record-attenuation-b light)
                   (gl-light-record-attenuation-c light))
      (uniform-1f! program (format "nonAmbientLightCutoffs[~a]" index)
                   (gl-light-record-attenuation-cutoff light))
      (uniform-1f! program (format "nonAmbientLightRanges[~a]" index)
                   (gl-light-record-range light))
      (uniform-1f! program (format "nonAmbientLightInnerAngles[~a]" index)
                   (gl-light-record-inner-angle light))
      (uniform-1f! program (format "nonAmbientLightOuterAngles[~a]" index)
                   (gl-light-record-outer-angle light)))
    (upload-gl-shadow-uniforms/current! program material selected shadow-samples
                                        fallback-shadow-texture)))

;; Every sampled map is associated by its stable authored light id rather than
;; by a positional coincidence in the light list.  `selected` is the packed
;; non-ambient stream consumed by mesh-lit.frag; ambient lights therefore do
;; not disturb the shader index recorded for a shadow map.
(define (upload-gl-shadow-uniforms/current! program material selected shadow-samples
                                            fallback-shadow-texture)
  (uniform-1i! program "materialReceivesShadow"
               (if (material3d-receives-shadow? material) 1 0))
  (define indexed-samples
    (for/list ([sample (in-list shadow-samples)]
               #:do [(define index
                       (for/first ([record (in-list selected)] [index (in-naturals)]
                                   #:when (eq? (gl-light-record-id record)
                                               (gl-shadow-sample-light-id sample)))
                         index))]
               #:when index)
      (cons index sample)))
  (unless (<= (length indexed-samples) (opengl3d-limit 'shadow-maps))
    (raise-arguments-error 'opengl-renderer3d
                           "at most eight shadow maps mapped to active lights"
                           "shadow-map-count" (length indexed-samples)))
  (unless (gl-texture? fallback-shadow-texture)
    (raise-arguments-error 'opengl-renderer3d
                           "a live fallback shadow texture"
                           "fallback-shadow-texture" fallback-shadow-texture))
  ;; The shader has eight sampler declarations even when this frame has no
  ;; shadow maps. Bind an owned depth texture at a reserved ninth unit and
  ;; point every slot there before real maps override the selected slots.
  ;; This keeps macOS from validating an inactive sampler against unit zero's
  ;; colour texture.
  (glActiveTexture (+ GL_TEXTURE0 (opengl3d-limit 'shadow-maps)))
  (glBindTexture GL_TEXTURE_2D (gl-resource-id fallback-shadow-texture))
  (for ([slot (in-range (opengl3d-limit 'shadow-maps))])
    (uniform-1i! program (format "shadowMap~a" slot)
                 (opengl3d-limit 'shadow-maps)))
  ;; Always upload zero for an empty list: uniforms belong to programs rather
  ;; than draw calls, so leaving an old value would sample stale texture units.
  (uniform-1i! program "shadowMapCount" (length indexed-samples))
  (for ([indexed (in-list indexed-samples)] [slot (in-naturals)])
    (define light-index (car indexed))
    (define sample (cdr indexed))
    (define target (gl-shadow-sample-target sample))
    (define camera (gl-shadow-sample-camera sample))
    (define settings (gl-shadow-sample-settings sample))
    (define bounds (gl-shadow-sample-bounds sample))
    (define size (gl-shadow-target-size target))
    (glActiveTexture (+ GL_TEXTURE0 slot))
    (glBindTexture GL_TEXTURE_2D
                   (gl-resource-id (gl-shadow-target-depth-texture target)))
    (uniform-1i! program (format "shadowMap~a" slot) slot)
    (uniform-1i! program (format "shadowMapLightIndices[~a]" slot) light-index)
    (uniform-mat4! program (format "shadowViewProjections[~a]" slot)
                   (camera3d-view-projection-matrix camera 1))
    (uniform-2f! program (format "shadowTexelSizes[~a]" slot)
                 (/ 1.0 size) (/ 1.0 size))
    (define bias (shadow-settings3d-bias settings))
    (uniform-1i! program (format "shadowBiasModes[~a]" slot) (if bias 1 0))
    (uniform-1f! program (format "shadowWorldNormalOffsets[~a]" slot)
                 (if bias (shadow-bias3d-world-normal-offset bias) 0))
    (uniform-1f! program (format "shadowSlopeScales[~a]" slot)
                 (if bias (shadow-bias3d-slope-scale bias) 0))
    (uniform-1f! program (format "shadowConstantDepthOffsets[~a]" slot)
                 (if bias (shadow-bias3d-constant-depth-offset bias) 0))
    (uniform-1f! program (format "shadowTexelWorldSizes[~a]" slot)
                 (shadow-bounds-texel-world-size bounds size))
    (uniform-1f! program (format "shadowDepthBiases[~a]" slot)
                 (shadow-settings3d-depth-bias settings))
    (uniform-1f! program (format "shadowNormalBiases[~a]" slot)
                 (shadow-settings3d-normal-bias settings))
    (uniform-1i! program (format "shadowPcfRadii[~a]" slot)
                 (shadow-settings3d-effective-pcf-radius settings)))
  ;; The caller releases these explicit per-opaque-draw bindings only after
  ;; the draw has sampled them. Leave unit zero active for ordinary callers.
  (glActiveTexture GL_TEXTURE0))

(define (shadow-bounds-texel-world-size bounds map-size)
  (define size (aabb3-size bounds))
  (max (/ (vec3-x size) map-size)
       (/ (vec3-y size) map-size)))

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
