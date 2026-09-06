#lang racket/base

;;;
;;; Runtime OpenGL Capability Probe
;;;

(require racket/list
         racket/set
         "api.rkt"
         "context-host.rkt")

(provide (struct-out opengl3d-info)
         probe-opengl3d-info
         opengl3d-info-required-capabilities
         opengl3d-info->datum
         opengl3d-info-supported?
         opengl3d-platform-diagnostics)

(struct opengl3d-info
  (version glsl-version vendor renderer profile extensions
           maximum-texture-size maximum-samples maximum-clip-distances
           maximum-vertex-attribs optional-features)
  #:transparent)

(define (gl-string enum)
  (define value (glGetString enum))
  (cond [(bytes? value) (bytes->string/utf-8 value #\?)]
        [else value]))

(define (gl-integer enum)
  (s32vector-ref (glGetIntegerv enum) 0))

(define (parse-version value)
  (define match
    (and (string? value)
         (regexp-match #px"([0-9]+)\\.([0-9]+)" value)))
  (and match
       (list (string->number (cadr match)) (string->number (caddr match)))))

(define (version>=? got wanted)
  (or (> (first got) (first wanted))
      (and (= (first got) (first wanted)) (>= (second got) (second wanted)))))

(define (current-extensions)
  ;; glGetString(GL_EXTENSIONS) is invalid in a core profile.  The backend
  ;; requires 3.2, so indexed extension queries are authoritative.  An empty
  ;; set is safer than probing the invalid legacy entry point after a driver
  ;; refuses the indexed query.
  (with-handlers ([exn? (lambda (_exception) (seteq))])
    (for/seteq ([index (in-range (gl-integer GL_NUM_EXTENSIONS))])
      (string->symbol (gl-string (glGetStringi GL_EXTENSIONS index))))))

(define (probe-current-opengl3d-info)
  (define version-string (gl-string GL_VERSION))
  (define glsl-string (gl-string GL_SHADING_LANGUAGE_VERSION))
  (define extensions (current-extensions))
  (define version (parse-version version-string))
  (define glsl-version (parse-version glsl-string))
  (opengl3d-info
   version glsl-version (gl-string GL_VENDOR) (gl-string GL_RENDERER)
   (if (and version (version>=? version '(3 2))) 'core-or-compatible 'legacy)
   extensions
   (gl-integer GL_MAX_TEXTURE_SIZE)
   (with-handlers ([exn? (lambda (_exception) 0)])
     (gl-integer GL_MAX_SAMPLES))
   (with-handlers ([exn? (lambda (_exception) 0)])
     (gl-integer GL_MAX_CLIP_DISTANCES))
   (gl-integer GL_MAX_VERTEX_ATTRIBS)
   (hasheq
    'multisample-framebuffer (and version (version>=? version '(3 0)))
    'pixel-buffer-object (and version (version>=? version '(2 1)))
    'sync-objects (and version (version>=? version '(3 2)))
    'timer-queries (or (set-member? extensions 'GL_ARB_timer_query)
                       (set-member? extensions 'GL_EXT_disjoint_timer_query))
    'debug-output (or (set-member? extensions 'GL_KHR_debug)
                      (set-member? extensions 'GL_ARB_debug_output))
    'srgb-framebuffer (or (and version (version>=? version '(3 0)))
                           (set-member? extensions 'GL_EXT_framebuffer_sRGB)))))

(define (probe-opengl3d-info host)
  (unless (gl-context-host? host)
    (raise-argument-error 'probe-opengl3d-info "gl-context-host?" host))
  (gl-context-host-call host probe-current-opengl3d-info))

(define (opengl3d-info-required-capabilities info)
  (unless (opengl3d-info? info)
    (raise-argument-error 'opengl3d-info-required-capabilities "opengl3d-info?" info))
  (define version (opengl3d-info-version info))
  (define glsl-version (opengl3d-info-glsl-version info))
  (hasheq 'opengl-3.2 (and version (version>=? version '(3 2)))
          'glsl-1.50 (and glsl-version (version>=? glsl-version '(1 50)))
          ;; The remainder are required core functionality at the stated
          ;; versions.  P-0 performs an executable test of each resource.
          'vbo (and version (version>=? version '(1 5)))
          'ebo (and version (version>=? version '(1 5)))
          'vao (and version (version>=? version '(3 0)))
          'fbo (and version (version>=? version '(3 0)))
          'rgba8 #t
          'depth-target #t
          'shader-program (and version (version>=? version '(2 0)))
          'read-pixels #t))

(define (opengl3d-info-supported? info)
  (for/and ([supported? (in-hash-values
                         (opengl3d-info-required-capabilities info))])
    supported?))

(define (opengl3d-info->datum info)
  (unless (opengl3d-info? info)
    (raise-argument-error 'opengl3d-info->datum "opengl3d-info?" info))
  (hasheq 'version (opengl3d-info-version info)
          'glsl-version (opengl3d-info-glsl-version info)
          'vendor (opengl3d-info-vendor info)
          'renderer (opengl3d-info-renderer info)
          'profile (opengl3d-info-profile info)
          'extensions (sort (set->list (opengl3d-info-extensions info)) symbol<?)
          'maximum-texture-size (opengl3d-info-maximum-texture-size info)
          'maximum-samples (opengl3d-info-maximum-samples info)
          'maximum-clip-distances (opengl3d-info-maximum-clip-distances info)
          'maximum-vertex-attribs (opengl3d-info-maximum-vertex-attribs info)
          'optional-features (opengl3d-info-optional-features info)
          'required-capabilities (opengl3d-info-required-capabilities info)))

(define (opengl3d-platform-diagnostics host [info #f])
  (define resolved (or info (probe-opengl3d-info host)))
  (hash-set (opengl3d-info->datum resolved)
            'platform (system-type)))
